/* ESP32-specific KMDF transport. SPDX-License-Identifier: MIT
 * Experimental: must be built with WDK and validated on a test machine.
 */
#include "driver.h"
#include "port.h"
#include "hci_packet.h"
#include "port.tmh"

NTSTATUS EspSerialQueryRemove(WDFIOTARGET Target)
{
    WdfIoTargetCloseForQueryRemove(Target);
    WdfDeviceSetFailed(WdfIoTargetGetDevice(Target), WdfDeviceFailedNoRestart);
    return STATUS_SUCCESS;
}

VOID EspSerialRemoveCanceled(WDFIOTARGET Target)
{
    /* Fail closed; explicitly restart the root devnode after the cable is stable.
     * Do not reopen another COM interface or resume a partial H4 frame. */
    WdfDeviceSetFailed(WdfIoTargetGetDevice(Target), WdfDeviceFailedNoRestart);
}

VOID EspSerialRemoveComplete(WDFIOTARGET Target)
{
    WdfIoTargetClose(Target);
    WdfDeviceSetFailed(WdfIoTargetGetDevice(Target), WdfDeviceFailedNoRestart);
}

NTSTATUS EspOpenSelectedSerial(WDFDEVICE Device, WDFIOTARGET *Target)
{
    WDFKEY key = NULL;
    WDFSTRING value = NULL;
    WDFIOTARGET candidate = NULL;
    WDF_OBJECT_ATTRIBUTES attributes;
    WDF_IO_TARGET_OPEN_PARAMS open;
    UNICODE_STRING selected, current;
    DECLARE_CONST_UNICODE_STRING(name, L"SerialDevicePath");
    DECLARE_CONST_UNICODE_STRING(prefix, L"\\??\\USB#VID_10C4&PID_EA60#");
    PWSTR list = NULL, cursor;
    BOOLEAN found = FALSE;
    NTSTATUS status;

    PAGED_CODE();
    *Target = NULL;
    /* One root bus instance: endpoint installed under service Parameters. */
    status = WdfDriverOpenParametersRegistryKey(WdfDeviceGetDriver(Device), KEY_READ,
                                               WDF_NO_OBJECT_ATTRIBUTES, &key);
    if (!NT_SUCCESS(status)) goto Done;
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);
    attributes.ParentObject = Device;
    status = WdfStringCreate(NULL, &attributes, &value);
    if (!NT_SUCCESS(status)) goto Done;
    status = WdfRegistryQueryString(key, &name, value);
    if (!NT_SUCCESS(status)) goto Done;
    WdfStringGetUnicodeString(value, &selected);
    if (selected.Length == 0 || !RtlPrefixUnicodeString(&prefix, &selected, TRUE)) {
        status = STATUS_INVALID_PARAMETER;
        goto Done;
    }
    /* Require the EXACT selected device interface to be currently registered.
     * Never fall back to the first COM port, nor accept arbitrary NT paths. */
    status = IoGetDeviceInterfaces(&GUID_DEVINTERFACE_COMPORT, NULL, 0, &list);
    if (!NT_SUCCESS(status)) goto Done;
    for (cursor = list; *cursor; cursor += wcslen(cursor) + 1) {
        RtlInitUnicodeString(&current, cursor);
        if (RtlEqualUnicodeString(&selected, &current, TRUE)) {
            found = TRUE;
            break;
        }
    }
    if (!found) {
        status = STATUS_NO_SUCH_DEVICE;
        goto Done;
    }
    status = WdfIoTargetCreate(Device, WDF_NO_OBJECT_ATTRIBUTES, &candidate);
    if (!NT_SUCCESS(status)) goto Done;
    WDF_IO_TARGET_OPEN_PARAMS_INIT_OPEN_BY_NAME(&open, &selected,
                                               GENERIC_READ | GENERIC_WRITE);
    open.ShareAccess = 0;
    open.EvtIoTargetQueryRemove = EspSerialQueryRemove;
    open.EvtIoTargetRemoveCanceled = EspSerialRemoveCanceled;
    open.EvtIoTargetRemoveComplete = EspSerialRemoveComplete;
    status = WdfIoTargetOpen(candidate, &open);
    if (!NT_SUCCESS(status)) goto Done;
    *Target = candidate;
    candidate = NULL;
Done:
    if (candidate) WdfObjectDelete(candidate);
    if (list) ExFreePool(list);
    if (value) WdfObjectDelete(value);
    if (key) WdfRegistryClose(key);
    DoTrace(LEVEL_INFO, TFLAG_UART, ("Selected ESP32 serial target: %!STATUS!", status));
    return status;
}

static NTSTATUS EspSerialIoctl(WDFIOTARGET Target, ULONG Code,
                               PVOID Buffer, ULONG Length)
{
    WDF_MEMORY_DESCRIPTOR input;
    WDF_REQUEST_SEND_OPTIONS options;
    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&input, Buffer, Length);
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_SEC(2));
    return WdfIoTargetSendIoctlSynchronously(Target, NULL, Code,
                                            &input, NULL, &options, NULL);
}

static NTSTATUS EspReadExact(WDFIOTARGET Target, PUCHAR Buffer, ULONG Length)
{
    ULONG offset = 0;
    ULONG_PTR received;
    WDF_MEMORY_DESCRIPTOR output;
    WDF_REQUEST_SEND_OPTIONS options;
    NTSTATUS status;
    ULONGLONG deadline = KeQueryInterruptTime() + 3ULL * 10000000ULL;
    while (offset < Length && KeQueryInterruptTime() < deadline) {
        received = 0;
        WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&output, Buffer + offset, Length - offset);
        WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
        WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_MS(250));
        status = WdfIoTargetSendReadSynchronously(Target, NULL, &output, NULL,
                                                 &options, &received);
        if (!NT_SUCCESS(status) && status != STATUS_IO_TIMEOUT && status != STATUS_TIMEOUT)
            return status;
        if (received > Length - offset) return STATUS_DATA_ERROR;
        offset += (ULONG)received;
    }
    return offset == Length ? STATUS_SUCCESS : STATUS_IO_TIMEOUT;
}

static NTSTATUS EspVerifyReset(WDFIOTARGET Target)
{
    UCHAR reset[] = {1, 3, 0x0c, 0};
    UCHAR header[3], event[257];
    WDF_MEMORY_DESCRIPTOR data;
    WDF_REQUEST_SEND_OPTIONS options;
    ULONG_PTR sent = 0;
    ULONG count;
    NTSTATUS status;
    WDF_MEMORY_DESCRIPTOR_INIT_BUFFER(&data, reset, sizeof(reset));
    WDF_REQUEST_SEND_OPTIONS_INIT(&options, WDF_REQUEST_SEND_OPTION_TIMEOUT);
    WDF_REQUEST_SEND_OPTIONS_SET_TIMEOUT(&options, WDF_REL_TIMEOUT_IN_SEC(2));
    status = WdfIoTargetSendWriteSynchronously(Target, NULL, &data, NULL, &options, &sent);
    if (!NT_SUCCESS(status)) return status;
    if (sent != sizeof(reset)) return STATUS_DEVICE_DATA_ERROR;
    for (count = 0; count < 8; ++count) {
        status = EspReadExact(Target, header, sizeof(header));
        if (!NT_SUCCESS(status)) return status;
        if (header[0] != 4) return STATUS_DEVICE_PROTOCOL_ERROR;
        event[0] = header[1];
        event[1] = header[2];
        if (header[2]) {
            status = EspReadExact(Target, event + 2, header[2]);
            if (!NT_SUCCESS(status)) return status;
        }
        if (!EspHciPayloadValid(4, event, (size_t)2 + header[2]))
            return STATUS_DEVICE_PROTOCOL_ERROR;
        /* Command Complete: num-command-packets, opcode LE, status. */
        if (event[0] == 0x0e && event[1] >= 4 && event[3] == 3 && event[4] == 0x0c)
            return event[5] == 0 ? STATUS_SUCCESS : STATUS_DEVICE_NOT_READY;
    }
    return STATUS_DEVICE_PROTOCOL_ERROR;
}

BOOLEAN EspInitializeSerial(WDFIOTARGET Target, BOOLEAN VerifyController)
{
    SERIAL_BAUD_RATE baud = {115200};
    SERIAL_LINE_CONTROL line = {STOP_BIT_1, NO_PARITY, 8};
    SERIAL_HANDFLOW flow;
    SERIAL_TIMEOUTS timeouts;
    LARGE_INTEGER delay;
    ULONG purge = SERIAL_PURGE_RXABORT | SERIAL_PURGE_RXCLEAR |
                  SERIAL_PURGE_TXABORT | SERIAL_PURGE_TXCLEAR;
    NTSTATUS status;
    PAGED_CODE();
    RtlZeroMemory(&flow, sizeof(flow)); /* No DTR, RTS, CTS, DSR, or XON/XOFF. */
    RtlZeroMemory(&timeouts, sizeof(timeouts));
    timeouts.ReadIntervalTimeout = MAXULONG;
    timeouts.ReadTotalTimeoutConstant = 100;
    timeouts.WriteTotalTimeoutConstant = 2000;
    status = EspSerialIoctl(Target, IOCTL_SERIAL_SET_HANDFLOW, &flow, sizeof(flow));
    if (!NT_SUCCESS(status)) goto Done;
    status = EspSerialIoctl(Target, IOCTL_SERIAL_SET_BAUD_RATE, &baud, sizeof(baud));
    if (!NT_SUCCESS(status)) goto Done;
    status = EspSerialIoctl(Target, IOCTL_SERIAL_SET_LINE_CONTROL, &line, sizeof(line));
    if (!NT_SUCCESS(status)) goto Done;
    status = EspSerialIoctl(Target, IOCTL_SERIAL_SET_TIMEOUTS, &timeouts, sizeof(timeouts));
    if (!NT_SUCCESS(status)) goto Done;
    if (VerifyController) {
        /* USB-UART opens can pulse reset on some DevKits. Drain boot text ONLY
         * before the initial handshake, never inside an active H4 stream. */
        delay.QuadPart = -2LL * 10000000LL;
        KeDelayExecutionThread(KernelMode, FALSE, &delay);
        status = EspSerialIoctl(Target, IOCTL_SERIAL_PURGE, &purge, sizeof(purge));
        if (!NT_SUCCESS(status)) goto Done;
        status = EspVerifyReset(Target);
    }
Done:
    DoTrace(LEVEL_INFO, TFLAG_UART, ("ESP32 serial initialization: %!STATUS!", status));
    return NT_SUCCESS(status);
}
