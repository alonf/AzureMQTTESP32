cmake_minimum_required(VERSION 3.16)

# Add the path to the components directory
# Ensure this path is relative to the root of your project
set(EXTRA_COMPONENT_DIRS 
    ${CMAKE_SOURCE_DIR}/components 
    $ENV{IDF_PATH}/examples/common_components/protocol_examples_common
)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(mqtt_azure_iot)

# Embed the certificate and key files into the binary
target_add_binary_data(mqtt_azure_iot.elf "main/espDeviceCert.pem" TEXT)
target_add_binary_data(mqtt_azure_iot.elf "main/espDeviceCert.key" TEXT)
target_add_binary_data(mqtt_azure_iot.elf "main/brokerCert.pem" TEXT)
