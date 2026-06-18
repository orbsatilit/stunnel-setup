#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Установка stunnel сервера${NC}"
echo -e "${GREEN}========================================${NC}"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ошибка: Этот скрипт должен запускаться от root (sudo)${NC}"
   exit 1
fi

# Запрос IP адреса сервера
echo -e "${YELLOW}Введите IP адрес вашего сервера (или домен):${NC}"
read -p "> " SERVER_IP

if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}Ошибка: IP адрес не может быть пустым${NC}"
    exit 1
fi

echo -e "${YELLOW}Введите порт для stunnel (по умолчанию 443):${NC}"
read -p "> " STUNNEL_PORT
STUNNEL_PORT=${STUNNEL_PORT:-443}

echo -e "${YELLOW}Введите порт SSH (по умолчанию 22):${NC}"
read -p "> " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

echo -e "${GREEN}Настройка:${NC}"
echo -e "  IP сервера: ${SERVER_IP}"
echo -e "  Порт stunnel: ${STUNNEL_PORT}"
echo -e "  Порт SSH: ${SSH_PORT}"
echo ""
echo -e "${YELLOW}Продолжить установку? (y/n)${NC}"
read -p "> " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Установка отменена${NC}"
    exit 0
fi

# Установка stunnel
echo -e "${GREEN}[1/5] Установка stunnel...${NC}"
apt update
apt install stunnel4 openssl -y

# Остановка существующей службы
echo -e "${GREEN}[2/5] Остановка старой службы...${NC}"
systemctl stop stunnel4 2>/dev/null
killall stunnel4 2>/dev/null

# Создание сертификата
echo -e "${GREEN}[3/5] Создание SSL сертификата...${NC}"
mkdir -p /etc/stunnel/certs
openssl req -x509 -newkey rsa:2048 -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem -nodes -days 3650 -subj "/CN=${SERVER_IP}" 2>/dev/null
chmod 600 /etc/stunnel/stunnel.pem
chown stunnel4:stunnel4 /etc/stunnel/stunnel.pem 2>/dev/null

# Создание конфигурации
echo -e "${GREEN}[4/5] Создание конфигурации...${NC}"
cat > /etc/stunnel/stunnel.conf << EOF
; stunnel серверная конфигурация
; Автоматически сгенерировано $(date)

pid = /var/run/stunnel4/stunnel4.pid
output = /var/log/stunnel4/stunnel4.log
setuid = stunnel4
setgid = stunnel4

; Отключаем проверку для самоподписанных сертификатов
verify = 0

; Основной сервис - SSH туннель
[ssh-tunnel]
accept = 0.0.0.0:${STUNNEL_PORT}
connect = 127.0.0.1:${SSH_PORT}
cert = /etc/stunnel/stunnel.pem
client = no
EOF

# Создание директорий
echo -e "${GREEN}[5/5] Настройка прав и запуск...${NC}"
mkdir -p /var/run/stunnel4
mkdir -p /var/log/stunnel4
chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null
chown stunnel4:stunnel4 /var/log/stunnel4 2>/dev/null

# Включение автозапуска
systemctl daemon-reload
systemctl enable stunnel4 2>/dev/null

# Запуск
systemctl restart stunnel4

# Проверка
sleep 2
if systemctl is-active --quiet stunnel4; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ stunnel успешно установлен и запущен!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Статус:${NC}"
    systemctl status stunnel4 --no-pager | head -5
    echo ""
    echo -e "${GREEN}Проверка порта:${NC}"
    ss -tlnp | grep ${STUNNEL_PORT}
    echo ""
    echo -e "${GREEN}Информация для подключения:${NC}"
    echo -e "  Сервер: ${SERVER_IP}"
    echo -e "  Порт: ${STUNNEL_PORT}"
    echo -e "  Сервис: SSH"
    echo ""
    echo -e "${YELLOW}Не забудьте открыть порт в брандмауэре:${NC}"
    echo -e "  sudo ufw allow ${STUNNEL_PORT}/tcp"
    echo -e "  sudo iptables -A INPUT -p tcp --dport ${STUNNEL_PORT} -j ACCEPT"
else
    echo -e "${RED}❌ Ошибка: stunnel не запустился!${NC}"
    echo -e "${YELLOW}Проверьте логи:${NC}"
    journalctl -u stunnel4 -n 20 --no-pager
fi
