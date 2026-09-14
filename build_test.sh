#!/bin/bash
docker build -t testxrdp .
docker run -d --name test_container testxrdp
sleep 2
docker exec test_container cat /etc/xrdp/xrdp.ini | grep "port"
docker stop test_container
docker rm test_container
