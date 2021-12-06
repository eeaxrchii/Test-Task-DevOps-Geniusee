#!/bin/bash

yum -y update
yum -y install httpd

cat <<EOF > /var/www/html/index.html
<html>
<body>
<h1>Hello World</h1>
</body>
</html>
EOF

sudo service httpd start
chlconfig httpd on