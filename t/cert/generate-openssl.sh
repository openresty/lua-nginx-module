#! /bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"

SUBJECT="/C=US/ST=California/L=Mountain View/O=OpenResty Inc"

PASSWORD=${PASSWORD:-openresty}

openssl genrsa -des3 -passout "pass:$PASSWORD" -out server.key 2048
openssl rsa -passin "pass:$PASSWORD" -in server.key -out server.unsecure.key
openssl req -passin "pass:$PASSWORD" -new -subj "$SUBJECT/CN=server" -key server.key -out server.csr


openssl genrsa -des3 -passout "pass:$PASSWORD" -out client.key 2048
openssl rsa -passin "pass:$PASSWORD" -in client.key -out client.unsecure.key
openssl req -passin "pass:$PASSWORD" -new -subj "$SUBJECT/CN=client" -key client.key -out client.csr


openssl req -passin "pass:$PASSWORD" -passout "pass:$PASSWORD" -new -x509 -subj "$SUBJET/CN=ca"  -keyout ca.key -out ca.crt
openssl x509 -req -sha256 -days 30650 -passin "pass:$PASSWORD" -in client.csr  -CA ca.crt -CAkey ca.key -set_serial 1 -out client.crt
openssl x509 -req -sha256 -days 30650 -passin "pass:$PASSWORD" -in server.csr  -CA ca.crt -CAkey ca.key -set_serial 2 -out server.crt


openssl pkcs12 -passin "pass:$PASSWORD" -passout "pass:$PASSWORD" -export -clcerts -in client.crt -inkey client.key -out client.p12
openssl pkcs12 -passin "pass:$PASSWORD" -passout "pass:$PASSWORD" -export -in client.crt -inkey client.key -out  client.pfx
openssl x509 -in client.crt -out client.cer
openssl x509 -in server.crt -out server.cer

