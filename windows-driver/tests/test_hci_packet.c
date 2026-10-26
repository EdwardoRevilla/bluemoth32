/* Host-mode tests of the exact header used by the driver. No WDK required.
 * Build from a VS x64 Native Tools prompt:
 * cl /nologo /W4 /WX tests\test_hci_packet.c /Fe:out\test_hci_packet.exe
 */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../src/hci_packet.h"

int main(void)
{
    unsigned char data[1026];
    size_t length, payload;
    memset(data, 0, sizeof(data));
    assert(!EspHciPayloadValid(1, NULL, 3));
    assert(!EspHciPayloadValid(3, data, 3));
    assert(!EspHciPayloadValid(5, data, 4));
    /* Exhaust header length boundaries, including maximum and one byte beyond. */
    for (payload = 0; payload < 256; ++payload) {
        data[2] = (unsigned char)payload;
        for (length = 0; length <= 259; ++length)
            assert(EspHciPayloadValid(1, data, length) == (length == 3 + payload));
        data[1] = (unsigned char)payload;
        for (length = 0; length <= 258; ++length)
            assert(EspHciPayloadValid(4, data, length) == (length == 2 + payload));
    }
    for (payload = 0; payload <= 1022; ++payload) {
        data[2] = (unsigned char)(payload & 255);
        data[3] = (unsigned char)(payload >> 8);
        assert(EspHciPayloadValid(2, data, 4 + payload) == (payload <= 1021));
        assert(!EspHciPayloadValid(2, data, 3 + payload));
        if (payload <= 1020) assert(!EspHciPayloadValid(2, data, 5 + payload));
    }
    data[2] = data[3] = 255;
    assert(!EspHciPayloadValid(2, data, 4));
    puts("PASS: native HCI packet limits, exact lengths, type separation and boundaries");
    return 0;
}
