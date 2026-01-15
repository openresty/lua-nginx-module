openssl req -new -newkey rsa:1024 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=California/L=San Francisco/O=OpenResty/CN=test2.com/emailAddress=openresty@gmail.com" \
    -keyout test-rsa1024.key -out test-rsa1024.crt
