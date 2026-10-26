/* SPDX-License-Identifier: MIT */
#ifndef ESP32_PORT_H
#define ESP32_PORT_H
EVT_WDF_IO_TARGET_QUERY_REMOVE EspSerialQueryRemove;
EVT_WDF_IO_TARGET_REMOVE_CANCELED EspSerialRemoveCanceled;
EVT_WDF_IO_TARGET_REMOVE_COMPLETE EspSerialRemoveComplete;
NTSTATUS EspOpenSelectedSerial(WDFDEVICE Device, WDFIOTARGET *Target);
BOOLEAN EspInitializeSerial(WDFIOTARGET Target, BOOLEAN VerifyController);
#endif
