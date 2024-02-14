#pragma once
#include <string>

namespace AzureEventGrid
{
    class IoTClientConfig 
    {
    private:
        std::string _brokerUri;
        std::string _clientId;
        std::string _username;

        const uint8_t* _clientCert;
        size_t _clientCertLen;
        const uint8_t* _clientKey;
        size_t _clientKeyLen;
        const uint8_t* _brokerCert;
        size_t _brokerCertLen;

    public:
        // Constructor
        IoTClientConfig()
            : _clientCert(nullptr), _clientCertLen(0),
              _clientKey(nullptr), _clientKeyLen(0),
              _brokerCert(nullptr), _brokerCertLen(0) {}

        // Setters
        void SetBrokerUri(const std::string& uri) { _brokerUri = uri; }
        void SetClientId(const std::string& id) { _clientId = id; }
        void SetUsername(const std::string& name) { _username = name; }
        void SetClientCert(const uint8_t* cert, size_t len) { _clientCert = cert; _clientCertLen = len; }
        void SetClientKey(const uint8_t* key, size_t len) { _clientKey = key; _clientKeyLen = len; }
        void SetBrokerCert(const uint8_t* cert, size_t len) { _brokerCert = cert; _brokerCertLen = len; }

        // Getters
        const char *GetBrokerUri() const { return _brokerUri.c_str(); }
        const char *GetClientId() const { return _clientId.c_str(); }
        const char *GetUsername() const { return _username.c_str(); }
        const char* GetClientCert() const { return reinterpret_cast<const char*>(_clientCert); }
        size_t GetClientCertLength() const { return _clientCertLen; }
        const char* GetClientKey() const { return reinterpret_cast<const char*>(_clientKey); }
        size_t GetClientKeyLength() const { return _clientKeyLen; }
        const char* GetBrokerCert() const { return reinterpret_cast<const char*>(_brokerCert); }
        size_t GetBrokerCertLength() const { return _brokerCertLen; }
    };
}
