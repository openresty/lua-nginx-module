openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=California/L=San Francisco/O=OpenResty/CN=test2.com/emailAddress=openresty@gmail.com" \
    -keyout test2.key -out test2.crt
