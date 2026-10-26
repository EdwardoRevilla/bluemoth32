/*++

Copyright (c) Microsoft Corporation All Rights Reserved

Module Name:

    public.h

Abstract:

    This module contains the common declarations shared by driver
    and user applications.

Environment:

    user and kernel

--*/

#ifndef __PUBLIC_H
#define __PUBLIC_H

#ifdef DEFINE_GUID

//
// Vendor: Define a device interface GUID for Bluetooth Radion On/off.
// Need to use uuidgen to create your own GUID instead of reusing this one.
//
DEFINE_GUID(GUID_DEVINTERFACE_BLUETOOTH_RADIO_ONOFF_VENDOR_SPECIFIC,
        0x20adbc56, 0x59b4, 0x438d, 0x9a, 0xde, 0xa6, 0x85, 0xbb, 0xe2, 0xd3, 0xa0);
//{20adbc56-59b4-438d-9ade-a685bbe2d3a0}

#endif // #ifdef DEFINE_GUID 


//
// IOCTL definitions to support Radio on/off
//
#define FILE_DEVICE_BUSENUM       FILE_DEVICE_BUS_EXTENDER
#define BUSENUM_IOCTL(id, access) CTL_CODE(FILE_DEVICE_BUSENUM, \
                                           (id),                \
                                           METHOD_BUFFERED,     \
                                           access)

#define IOCTL_BUSENUM_SET_RADIO_ONOFF_VENDOR_SPECFIC        BUSENUM_IOCTL(0x1, FILE_WRITE_DATA)

#endif
