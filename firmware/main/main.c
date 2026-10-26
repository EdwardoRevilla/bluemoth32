// Experimental ESP32 H4 transport; reviewed against ESP-IDF v5.5.1.
// No host stack runs here: the external host owns HCI commands and credits.
#include "sdkconfig.h"
#include "esp_bt.h"
#include "esp_err.h"
#include "esp_idf_version.h"
#include "nvs_flash.h"
#include "driver/uart.h"
#include "esp_private/periph_ctrl.h"
#include "soc/uhci_periph.h"

#if !CONFIG_IDF_TARGET_ESP32
#error "This prototype targets ESP32-WROOM-32 only"
#endif
#if ESP_IDF_VERSION != ESP_IDF_VERSION_VAL(5, 5, 1)
#error "Use ESP-IDF v5.5.1; other versions require a transport review"
#endif
#if !CONFIG_BTDM_CTRL_HCI_MODE_UART_H4 || CONFIG_BTDM_CTRL_HCI_UART_NO != 1
#error "Use the supplied H4/UART1 sdkconfig.defaults"
#endif
#if !CONFIG_ESP_CONSOLE_NONE
#error "The console must not share the binary HCI pins"
#endif

void app_main(void)
{
    // Fail visibly to a debugger if NVS is invalid; never erase it implicitly.
    ESP_ERROR_CHECK(nvs_flash_init());
    periph_module_enable(PERIPH_UART1_MODULE);
    periph_module_enable(PERIPH_UHCI0_MODULE);
    // UART1 is routed to the DevKit's existing USB-UART TX/RX wires.
    // Do not install the application UART driver: the BT controller owns UART1.
    ESP_ERROR_CHECK(uart_set_pin(UART_NUM_1, 1, 3,
                                UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
    esp_bt_controller_config_t cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_bt_controller_init(&cfg));
    ESP_ERROR_CHECK(esp_bt_controller_enable(ESP_BT_MODE_BTDM));
    // No printf/ESP_LOG here. Diagnostic records belong on the PC or JTAG.
}
