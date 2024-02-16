#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <algorithm>
#include <cctype>
#include "esp_system.h"
#include "esp_netif.h"
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
#include "IIoTClient.h"
#include "esp_task_wdt.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/temperature_sensor.h"
#include "cJSON.h"

using namespace AzureEventGrid;

static const char *TAG = "AzureMQTTSExample";
static IIoTClient *_pAzureMqttIoTClient = nullptr;
const gpio_num_t LED_GPIO_PIN = GPIO_NUM_2;
temperature_sensor_handle_t temperatureSensor = nullptr;
TaskHandle_t g_mainTaskHandle;

extern const uint8_t espDeviceCert_pem_start[] asm("_binary_espDeviceCert_pem_start");
extern const uint8_t espDeviceCert_pem_end[] asm("_binary_espDeviceCert_pem_end");
extern const uint8_t espDeviceCert_key_start[] asm("_binary_espDeviceCert_key_start");
extern const uint8_t espDeviceCert_key_end[] asm("_binary_espDeviceCert_key_end");
extern const uint8_t brokerCert_pem_start[] asm("_binary_brokerCert_pem_start");
extern const uint8_t brokerCert_pem_end[] asm("_binary_brokerCert_pem_end");

volatile float g_temperature = 0.0;
volatile int g_delayBetweenTelemetry = 5000;

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"

void LoadCPU() 
{
    volatile int load;
    // Simple computation to load the CPU. Adjust the loop count for more load.
    for (int i = 0; i < (rand() % 1000000) + 500000; i++) 
    {
        load = esp_random(); // Using esp_random() to avoid optimizations removing the loop
        if (i % 10000 == 0) 
        { 
            vTaskDelay(1);
        }
    }
}

#pragma GCC diagnostic pop

void ReadTemperature(void *pvParameters) 
{
    while (1)
    {
        LoadCPU(); // Load the CPU to increase temperature
        
        // Get temperature
        float temperature = 0.0;
        temperature_sensor_get_celsius(temperatureSensor, &temperature);
        ESP_LOGI("TEMP", "Temperature: %.2f°C", temperature);

        g_temperature = temperature;
        
        vTaskDelay((rand() % 5000 + 500) / portTICK_PERIOD_MS); // Wait a random time
    }
}


static void DesiredPropertyCallback(IIoTClient *pClient, const std::string& propertyName, const std::string& propertyValue)
{
    ESP_LOGI(TAG, "Received desired property update %s=%s", propertyName.c_str(), propertyValue.c_str());

    if (propertyName == "delayBetweenTelemetry")
    {
        g_delayBetweenTelemetry = std::stoi(propertyValue) * 1000; //convert to milliseconds
        xTaskNotifyGive(g_mainTaskHandle);
    }
}

static void SetLight(bool state)
{
    ESP_LOGI(TAG, "Setting light to %s", state ? "on" : "off");
    gpio_set_level(LED_GPIO_PIN, state ? 1 : 0);
}

static std::string CommandCallback(IIoTClient *pClient, const std::string& commandName, const std::string& payload)
{
    ESP_LOGI(TAG, "Received command: %s with payload: %s", commandName.c_str(), payload.c_str());

    std::string commandNameLower = commandName;
    std::transform(std::begin(commandNameLower), std::end(commandNameLower), std::begin(commandNameLower),
                   [](unsigned char c){ return std::tolower(c); });


    cJSON* root = cJSON_ParseWithLength(payload.c_str(), payload.length());
    if (root == nullptr) 
    {
        ESP_LOGE(TAG, "Failed to parse JSON data");
        return "{\"result\":\"Error parsing JSON\"}";
    }

    if (commandNameLower == "light")
    {
        cJSON* state = cJSON_GetObjectItemCaseSensitive(root, "state");
        if (state == nullptr || !cJSON_IsString(state))
        {
            cJSON_Delete(root);
            return "{\"result\":\"Error parsing JSON\"}";
        }
        //else
        
        std::string stateValue = state->valuestring;
        // Convert state to lowercase for case-insensitive comparison
        std::transform(std::begin(stateValue), std::end(stateValue), std::begin(stateValue),
                        [](unsigned char c){ return std::tolower(c); });

        if (stateValue == "on")
        {
            SetLight(true);
            pClient->UpdateReportedProperties("light", "on");
        }
        else if (stateValue == "off")
        {
            SetLight(false);
            pClient->UpdateReportedProperties("light", "off");
        }
    }
    
    cJSON_Delete(root);
    return "{\"result\":\"OK\"}";
}

static void mqtt_app_start(void)
{

    ESP_LOGI(TAG, "Starting MQTT client for device %s", CONFIG_CLIENT_ID);
    ESP_LOGI(TAG, "Connecting to %s", CONFIG_BROKER_URI);

    

    IoTClientConfig config;
    config.SetBrokerUri(CONFIG_BROKER_URI);
    config.SetClientId(CONFIG_CLIENT_ID);
    config.SetClientCert(espDeviceCert_pem_start, espDeviceCert_pem_end - espDeviceCert_pem_start);
    config.SetClientKey(espDeviceCert_key_start, espDeviceCert_key_end - espDeviceCert_key_start);
    config.SetBrokerCert(brokerCert_pem_start, brokerCert_pem_end - brokerCert_pem_start);

    _pAzureMqttIoTClient = IIoTClient::Initialize(config, DesiredPropertyCallback, CommandCallback);

    ESP_LOGI(TAG, "[APP] Free memory: %" PRIu32 " bytes", esp_get_free_heap_size());

    xTaskCreate(ReadTemperature, "ReadTemperature", 4096, nullptr, 5, nullptr);

    //keep the handle to be able to interrupt the delay between telemetry publising when a desired property is received
    g_mainTaskHandle = xTaskGetCurrentTaskHandle();

    while (1)
    {
        _pAzureMqttIoTClient->SendTelemetry("temperature", "{\"value\":" + std::to_string(g_temperature) + "}");

        // Wait for the delay between telemetry
         ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(g_delayBetweenTelemetry)); 
    }
}

extern "C" void app_main(void)
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

    ESP_LOGI(TAG, "Setting up the LED GPIO pin: %d", LED_GPIO_PIN);

    // Configure the GPIO pin as output for the LED
    gpio_set_direction(LED_GPIO_PIN, GPIO_MODE_OUTPUT);
    
    ESP_LOGI(TAG, "Setting up the internal temperature sensor");
    //Configure the internal temperature sensor
    temperature_sensor_config_t temp_sensor_config = TEMPERATURE_SENSOR_CONFIG_DEFAULT(10, 50);
    
    auto ret = temperature_sensor_install(&temp_sensor_config, &temperatureSensor);
    if (ret != ESP_OK) 
    {
        ESP_LOGE(TAG, "Temperature sensor is not installed");
        return;
    }

    ret = temperature_sensor_enable(temperatureSensor);
    if (ret != ESP_OK) 
    {
        ESP_LOGE(TAG, "Could not enable temperature sensor");
        return;
    }

    mqtt_app_start();
}

