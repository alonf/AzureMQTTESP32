#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "esp_system.h"
#include "esp_partition.h"
#include "nvs_flash.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "protocol_examples_common.h"

#include "esp_log.h"
#include "mqtt_client.h"
#include "esp_tls.h"
#include "esp_ota_ops.h"
#include <sys/param.h>
#include "esp_sntp.h"
#include "AzureMqttIoTClient.h"

static const char *TAG = "AzureMQTTSExample";
static AzureMqttIoTClient *_pAzureMqttIoTClient = nullptr;

extern const uint8_t espDeviceCert_pem_start[] asm("_binary_espDeviceCert_pem_start");
extern const uint8_t espDeviceCert_pem_end[] asm("_binary_espDeviceCert_pem_end");
extern const uint8_t espDeviceCert_key_start[] asm("_binary_espDeviceCert_key_start");
extern const uint8_t espDeviceCert_key_end[] asm("_binary_espDeviceCert_key_end");
extern const uint8_t brokerCert_pem_start[] asm("_binary_brokerCert_pem_start");
extern const uint8_t brokerCert_pem_end[] asm("_binary_brokerCert_pem_end");

static void DesiredPropertyCallback(MqttIoTClient *pClient, const std::string& property, const std::string& value)
{
    ESP_LOGI(TAG, "Received desired property update %s=%s", property.c_str(), value.c_str());
}

static std::string CommandCallback(MqttIoTClient *pClient, const std::string& command, const std::string& payload)
{
    ESP_LOGI(TAG, "Received command %s=%s", command.c_str(), payload.c_str());
    pClient->UpdateReportedProperties("{\"commandStatus\":\"OK\"}");
    pClient->SendTelemetry("{\"command\":\"" + command + "\",\"payload\":\"" + payload + "\"}");

    return std::string("{\"result\":\"OK\"}");
}

static void mqtt_app_start(void)
{

    const esp_mqtt_client_config_t mqtt_cfg = 
    {
        .broker = 
        {
            .address.uri = CONFIG_BROKER_URI,
            .verification.certificate = (const char *)brokerCert_pem_start,
        },
        .credentials = 
        {
            .username = "espDevice",
            .client_id = "espDevice",
            .authentication = 
            {
                .certificate = (const char *)espDeviceCert_pem_start,
                .certificate_len = espDeviceCert_pem_end - espDeviceCert_pem_start,
                .key = (const char *)espDeviceCert_key_start,
                .key_len = espDeviceCert_key_end - espDeviceCert_key_start,
            },
        }
    };

    _pAzureMqttIoTClient = AzureMqttIoTClient::Initialize(mqtt_cfg, DesiredPropertyCallback, CommandCallback);

    ESP_LOGI(TAG, "[APP] Free memory: %" PRIu32 " bytes", esp_get_free_heap_size());
    
}

void app_main(void)
{
    ESP_LOGI(TAG, "[APP] Startup..");
    ESP_LOGI(TAG, "[APP] Free memory: %" PRIu32 " bytes", esp_get_free_heap_size());
    ESP_LOGI(TAG, "[APP] IDF version: %s", esp_get_idf_version());

    esp_log_level_set("*", ESP_LOG_INFO);
    esp_log_level_set("esp-tls", ESP_LOG_VERBOSE);
    esp_log_level_set("MQTT_CLIENT", ESP_LOG_VERBOSE);
    esp_log_level_set("MQTT_EXAMPLE", ESP_LOG_VERBOSE);
    esp_log_level_set("TRANSPORT_BASE", ESP_LOG_VERBOSE);
    esp_log_level_set("TRANSPORT", ESP_LOG_VERBOSE);
    esp_log_level_set("OUTBOX", ESP_LOG_VERBOSE);

    ESP_ERROR_CHECK(nvs_flash_init());
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    /* This helper function configures Wi-Fi or Ethernet, as selected in menuconfig.
     * Read "Establishing Wi-Fi or Ethernet Connection" section in
     * examples/protocols/README.md for more information about this function.
     */
    ESP_ERROR_CHECK(example_connect());

    mqtt_app_start();
}
