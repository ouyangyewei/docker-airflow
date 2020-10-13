#!/usr/bin/env bash

# User-provided configuration must always be respected.
#
# Therefore, this script must only derives Airflow AIRFLOW__ variables from other variables
# when the user did not provide their own configuration.

TRY_LOOP="20"

# Global defaults and back-compat
: "${AIRFLOW_HOME:="/usr/local/airflow"}"
: "${AIRFLOW__CORE__FERNET_KEY:=${FERNET_KEY:=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print(FERNET_KEY)")}}"
: "${AIRFLOW__CORE__EXECUTOR:=${EXECUTOR:-Sequential}Executor}"

# Load DAGs examples (default: Yes)
if [[ -z "$AIRFLOW__CORE__LOAD_EXAMPLES" && "${LOAD_EX:=n}" == n ]]; then
  AIRFLOW__CORE__LOAD_EXAMPLES=False
fi

export \
  AIRFLOW_HOME \
  AIRFLOW__CORE__EXECUTOR \
  AIRFLOW__CORE__FERNET_KEY \
  AIRFLOW__CORE__LOAD_EXAMPLES \

# Install custom python package if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    $(command -v pip) install --user -r /requirements.txt
fi

function pre_check() {
  if [[ -z "$MYSQL_HOST" ]]; then
    >&2 printf '%s\n' "FATAL: Variable MYSQL_HOST not set."
    exit 1;
  fi
  if [[ -z "$MYSQL_PORT" ]]; then
    >&2 printf '%s\n' "FATAL: Variable MYSQL_PORT not set."
    exit 1;
  fi
  if [[ -z "$MYSQL_USER" ]]; then
    >&2 printf '%s\n' "FATAL: Variable MYSQL_USER not set."
    exit 1;
  fi
  if [[ -z "$MYSQL_PASSWORD" ]]; then
    >&2 printf '%s\n' "FATAL: Variable MYSQL_PASSWORD not set."
    exit 1;
  fi
  if [[ -z "$AIRFLOW_DB" ]]; then
    >&2 printf '%s\n' "FATAL: Variable AIRFLOW_DB not set."
    exit 1;
  fi
  if [[ -z "$CELERY_DB" ]]; then
    >&2 printf '%s\n' "FATAL: Variable CELERY_DB not set."
    exit 1;
  fi
}

function wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z "$host" "$port" >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [ $j -ge $TRY_LOOP ]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name... $j/$TRY_LOOP"
    sleep 5
  done
}

LOG_FILE=$AIRFLOW_HOME/entrypoint.log
{
  echo "MYSQL_HOST=$MYSQL_HOST"
  echo "MYSQL_PORT=$MYSQL_PORT"
  echo "MYSQL_USER=$MYSQL_USER"
  echo "MYSQL_PASSWORD=$MYSQL_PASSWORD"
  echo "AIRFLOW_DB=$AIRFLOW_DB"
  echo "CELERY_DB=$CELERY_DB"
  echo "RABBITMQ_HOST=$RABBITMQ_HOST"
  echo "RABBITMQ_PORT=$RABBITMQ_PORT"
  echo "RABBITMQ_USER=$RABBITMQ_DEFAULT_USER"
  echo "RABBITMQ_PASSWORD=$RABBITMQ_DEFAULT_PASS"
  echo "RABBITMQ_VHOST=$RABBITMQ_DEFAULT_VHOST"
  echo "AIRFLOW_HOME=$AIRFLOW_HOME"
  echo "AIRFLOW__CORE__EXECUTOR=$AIRFLOW__CORE__EXECUTOR"
  echo "AIRFLOW__CORE__FERNET_KEY=$AIRFLOW__CORE__FERNET_KEY"
  echo "AIRFLOW__CORE__LOAD_EXAMPLES=$AIRFLOW__CORE__LOAD_EXAMPLES"
  echo "FERNET_KEY=$FERNET_KEY"
  echo "EXECUTOR=$EXECUTOR"
} > $LOG_FILE

# pre-check
pre_check;

# initialize database
if [ -z "$AIRFLOW__CORE__SQL_ALCHEMY_CONN" ]; then
  # wait for mysql response
  wait_for_port "MySQL" "$MYSQL_HOST" "$MYSQL_PORT"

  AIRFLOW__CORE__SQL_ALCHEMY_CONN="mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${AIRFLOW_DB}${MYSQL_EXTRAS}"
  export AIRFLOW__CORE__SQL_ALCHEMY_CONN
  echo "AIRFLOW__CORE__SQL_ALCHEMY_CONN=$AIRFLOW__CORE__SQL_ALCHEMY_CONN" >> $LOG_FILE
fi

# CeleryExecutor drives the need for a Celery broker, here Redis is used
if [ "$AIRFLOW__CORE__EXECUTOR" = "CeleryExecutor" ]; then
  # Check if the user has provided explicit Airflow configuration concerning the broker
  AIRFLOW__CELERY__BROKER_URL="amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@${RABBITMQ_HOST}:${RABBITMQ_PORT}/${RABBITMQ_DEFAULT_VHOST}"
  export AIRFLOW__CELERY__BROKER_URL
  echo "AIRFLOW__CELERY__BROKER_URL=$AIRFLOW__CELERY__BROKER_URL" >> $LOG_FILE

  # Check if the user has provided explicit Airflow configuration for the broker's connection to the database
  AIRFLOW__CELERY__RESULT_BACKEND="db+mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${CELERY_DB}${MYSQL_EXTRAS}"
  export AIRFLOW__CELERY__RESULT_BACKEND
  echo "AIRFLOW__CELERY__RESULT_BACKEND=$AIRFLOW__CELERY__RESULT_BACKEND" >> $LOG_FILE
fi

case "$1" in
  webserver)
    airflow initdb >> $LOG_FILE
    if [ "$AIRFLOW__CORE__EXECUTOR" = "LocalExecutor" ] || [ "$AIRFLOW__CORE__EXECUTOR" = "SequentialExecutor" ]; then
      # With the "Local" and "Sequential" executors it should all run in one container.
      airflow scheduler &
    fi
    exec airflow webserver
    ;;
  worker|scheduler)
    # Give the webserver time to run initdb.
    sleep 10
    exec airflow "$@"
    ;;
  flower)
    sleep 10
    exec airflow "$@"
    ;;
  version)
    exec airflow "$@"
    ;;
  *)
    # The command is something like bash, not an airflow subcommand. Just run it in the right environment.
    exec "$@"
    ;;
esac
