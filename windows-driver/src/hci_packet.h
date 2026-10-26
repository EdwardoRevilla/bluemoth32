/* ESP32 transport additions. SPDX-License-Identifier: MIT */
#ifndef ESP32_HCI_PACKET_H
#define ESP32_HCI_PACKET_H
#include <stddef.h>

/* H4 values, deliberately separate from the BTHX enumeration. No H4 type byte
 * is present in the BTHX payload passed to this function. */
static __inline int EspHciPayloadValid(unsigned int type,
                                     const unsigned char *data, size_t length)
{
    size_t payload;
    if (data == NULL) return 0;
    switch (type) {
    case 1: /* command */
        return length >= 3 && length <= 258 && length == (size_t)3 + data[2];
    case 2: /* ACL, little endian length; zero-length ACL is valid framing */
        if (length < 4 || length > 1025) return 0;
        payload = (size_t)data[2] | ((size_t)data[3] << 8);
        return payload <= 1021 && length == 4 + payload;
    case 4: /* event */
        return length >= 2 && length <= 257 && length == (size_t)2 + data[1];
    default:
        return 0;
    }
}
#endif
