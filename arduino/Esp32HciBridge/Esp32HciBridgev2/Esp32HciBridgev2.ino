/*
 * Experimental H4 <-> VHCI bridge for ORIGINAL ESP32-WROOM-32.
 * Compiled with Arduino-ESP32 3.3.3. Corrected build awaits hardware upload/test.
 * Select ESP32 Dev Module, upload speed 115200, then close Serial Monitor.
 * Binary serial protocol at 115200 8N1; no text messages on this channel.
 * Supports HCI Commands / ACL to controller and events / ACL from controller.
 * Not a Windows Bluetooth driver. No SCO/audio support in this prototype.
 */
#include <Arduino.h>
#include "esp_bt.h"
#include "esp32-hal-bt.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

#if !CONFIG_IDF_TARGET_ESP32
#error "Use an original ESP32-WROOM-32, not S2/S3/C3"
#endif
#if !CONFIG_BTDM_CTRL_HCI_MODE_VHCI
#error "This sketch requires the Arduino core's VHCI controller configuration"
#endif

static constexpr size_t MAX_PACKET = 1026;  // H4 type + ACL header + 1021 bytes
struct Packet {
  uint16_t length;
  uint8_t bytes[MAX_PACKET];
};
static QueueHandle_t controllerOutput;
static portMUX_TYPE faultMux = portMUX_INITIALIZER_UNLOCKED;
static bool failed = false;
static Packet inputPacket;
static size_t expected = 0;
static uint32_t lastByteAt = 0;

static void failClosed() {
  portENTER_CRITICAL(&faultMux);
  failed = true;
  portEXIT_CRITICAL(&faultMux);
}

static bool isFailed() {
  portENTER_CRITICAL(&faultMux);
  bool value = failed;
  portEXIT_CRITICAL(&faultMux);
  return value;
}

static void controllerReady() {
  // loop() checks esp_vhci_host_check_send_available() before each packet.
}

static int controllerReceived(uint8_t *data, uint16_t length) {
  // Called in controller task context. Never block or print in this callback.
  if (length == 0 || length > MAX_PACKET || isFailed()) {
    failClosed();
    return -1;
  }
  Packet packet;
  packet.length = length;
  memcpy(packet.bytes, data, length);
  if (xQueueSend(controllerOutput, &packet, 0) != pdTRUE) {
    // H4 has no safe recovery after loss. Stop rather than silently lose packets.
    failClosed();
    return -1;
  }
  return 0;
}

static esp_vhci_host_callback_t callbacks = {
  controllerReady,
  controllerReceived
};

void setup() {
  Serial.setRxBufferSize(4096);
  Serial.begin(115200);
  controllerOutput = xQueueCreate(16, sizeof(Packet));
  if (!controllerOutput || esp_bt_controller_get_status() != ESP_BT_CONTROLLER_STATUS_IDLE) {
    failClosed();
    return;
  }
  // Arduino initializes NVS before setup(). Do not initialize Bluedroid or BLEDevice.
  // btStart also forces the Arduino Bluetooth HAL into the linked image.
  // Its btInUse() prevents initArduino() from freeing BT memory before setup().
  if (!btStart() ||
      esp_vhci_host_register_callback(&callbacks) != ESP_OK) {
    failClosed();
  }
}

void loop() {
  if (isFailed()) {
    delay(100);  // Host sees timeout. Reset the board to recover.
    return;
  }

  // A bounded queue decouples controller callback from slow USB-UART writes.
  static Packet outputPacket;
  if (xQueueReceive(controllerOutput, &outputPacket, 0) == pdTRUE) {
    if (Serial.write(outputPacket.bytes, outputPacket.length) != outputPacket.length) {
      failClosed();
      return;
    }
  }

  // Keep a complete packet until the controller grants permission to send it.
  if (expected && inputPacket.length == expected) {
    if (esp_vhci_host_check_send_available()) {
      esp_vhci_host_send_packet(inputPacket.bytes, inputPacket.length);
      inputPacket.length = 0;
      expected = 0;
    }
    delay(1);
    return;
  }

  // Never guess packet boundaries after an incomplete transfer.
  if (inputPacket.length && uint32_t(millis() - lastByteAt) > 2000) {
    failClosed();
    return;
  }
  while (Serial.available()) {
    int value = Serial.read();
    if (value < 0) break;
    lastByteAt = millis();
    if (inputPacket.length >= MAX_PACKET) {
      failClosed();
      return;
    }
    inputPacket.bytes[inputPacket.length++] = uint8_t(value);
    uint8_t kind = inputPacket.bytes[0];
    if (kind != 1 && kind != 2) {
      failClosed();
      return;
    }
    if (kind == 1 && inputPacket.length == 4) {
      expected = 4 + inputPacket.bytes[3];
    } else if (kind == 2 && inputPacket.length == 5) {
      expected = 5 + inputPacket.bytes[3] + (uint16_t(inputPacket.bytes[4]) << 8);
      if (expected > MAX_PACKET) {
        failClosed();
        return;
      }
    }
    if (expected && inputPacket.length == expected) break;
  }
  delay(1);
}
