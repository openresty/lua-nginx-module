#!/bin/bash

# Set variables
SUBJECT="/C=CN/ST=Guangdong/L=ShenZhen/O=OpenResty/OU=OpenResty/CN=test.com/emailAddress=guanglinlv@gmail.com"
DAYS=49000  # Approximately 134 years
KEY_FILE="test_passphrase.key"
CERT_FILE="test_passphrase.crt"
PASSWORD="123456"

# Generate a new 2048-bit RSA private key, encrypted with the password
openssl genrsa -aes256 -passout pass:$PASSWORD -out $KEY_FILE 2048

# Generate a new self-signed certificate
openssl req -x509 -new -nodes -key $KEY_FILE -sha256 -days $DAYS \
    -out $CERT_FILE -subj "$SUBJECT" -passin pass:$PASSWORD

# Display information about the new certificate
openssl x509 -in $CERT_FILE -text -noout

echo "New 2048-bit certificate generated successfully!"
echo "Private key (encrypted): $KEY_FILE"
echo "Certificate: $CERT_FILE"

