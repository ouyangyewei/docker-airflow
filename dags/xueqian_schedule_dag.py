
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash_operator import BashOperator

# Define DAG
default_args = {
    'owner': 'yewei.oyyw',
    'start_date': datetime(2020, 9, 28),
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}
dag = DAG('xueqian_schedule_dag', default_args=default_args, schedule_interval=timedelta(seconds=1))

# Task_1
task1 = BashOperator(
    task_id='Task1',
    bash_command='date',
    dag=dag)
# Task_2
task2 = BashOperator(
    task_id='Task2',
    bash_command='sleep 5',
    retries=3,
    dag=dag)
# Task_3
task3 = BashOperator(
    task_id='Task3',
    bash_command="echo 'hello world'",
    dag=dag)

# Task_1 -> Task_2 -> Task_3
task1 >> task2 >> task3
