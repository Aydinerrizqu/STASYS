idf_component_register(
    SRCS "main.cpp" "provisioning/provisioning.cpp"
    INCLUDE_DIRS "." "provisioning"
    REQUIRES app_protocol sensors system_config bt nvs_flash driver
)
