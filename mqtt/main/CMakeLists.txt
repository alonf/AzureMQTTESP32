idf_component_register(SRCS "app_main.cpp"
                    INCLUDE_DIRS "."
                    REQUIRES mqtt nvs_flash esp_netif protocol_examples_common app_update AzureMqttIoTClient)
