#!/bin/bash

commit=true
origin=$(git remote get-url origin)
if [[ $origin == *statsig-io/statuspage* ]]
then
  commit=false
fi

KEYSARRAY=()
URLSARRAY=()

urlsConfig="./urls.cfg"
echo "Reading $urlsConfig"
while read -r line
do
  echo "  $line"
  IFS='=' read -ra TOKENS <<< "$line"
  KEYSARRAY+=(${TOKENS[0]})
  URLSARRAY+=(${TOKENS[1]})
done < "$urlsConfig"

echo "***********************"
echo "Starting health checks with ${#KEYSARRAY[@]} configs:"

mkdir -p logs
mkdir -p state   # <--- aquí guardamos los últimos estados

for (( index=0; index < ${#KEYSARRAY[@]}; index++))
do
  key="${KEYSARRAY[index]}"
  url="${URLSARRAY[index]}"
  echo "  $key=$url"

  for i in 1 2 3 4; 
  do
    response=$(curl --write-out '%{http_code}' --silent --output /dev/null $url)
    if [ "$response" -eq 200 ] || [ "$response" -eq 202 ] || [ "$response" -eq 301 ] || [ "$response" -eq 302 ] || [ "$response" -eq 307 ]; then
      result="success"
    else
      result="failed"
    fi
    if [ "$result" = "success" ]; then
      break
    fi
    sleep 5
  done

  dateTime=$(date +'%Y-%m-%d %H:%M')

  # === Estado previo/actual ===
  state_file="state/${key}.status"
  prev_state="unknown"
  if [ -f "$state_file" ]; then
    prev_state=$(cat "$state_file")
  fi

  if [ "$result" != "$prev_state" ]; then
    # Ha cambiado -> enviar notificación Telegram
    if [ "$result" = "failed" ]; then
      msg="⚠️ Servicio ${key} (${url}) está DOWN (HTTP=$response)"
    else
      msg="✅ Servicio ${key} (${url}) volvió UP (HTTP=$response)"
    fi

    curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d chat_id="${TELEGRAM_CHAT_ID}" \
         --data-urlencode "text=${msg}"

    echo "$result" > "$state_file"
  fi

  if [[ $commit == true ]]
  then
    echo $dateTime, $result >> "logs/${key}_report.log"
    echo "$(tail -2000 logs/${key}_report.log)" > "logs/${key}_report.log"
  else
    echo "    $dateTime, $result"
  fi
done

if [[ $commit == true ]]
then
  git config --global user.name 'Vijaye Raji'
  git config --global user.email 'vijaye@statsig.com'
  git add -A --force logs/ state/
  git commit -am '[Automated] Update Health Check Logs'
  git push
fi
