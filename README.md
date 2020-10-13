### MySQL Argument
```sql
explicit_defaults_for_timestamp = ON
```

### docker build
```bash
docker build --rm -t docker-airflow:1.0 .
```

### docker run
```bash
docker run -d -p 8080:8080 docker-airflow:1.0 webserver
```

### docker compose
```bash
docker-compose -f docker-compose-CeleryExecutor.yml up -d
```