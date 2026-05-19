import pymssql
from config import Config

def get_connection():
    return pymssql.connect(
        server=Config.DB_SERVER,
        user=Config.DB_USERNAME,
        password=Config.DB_PASSWORD,
        database=Config.DB_DATABASE,
        port=Config.DB_PORT
    )

def fetch_all(query, params=None):
    conn = get_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute(query, params or ())
    rows = cursor.fetchall()
    conn.close()
    return rows

def fetch_one(query, params=None):
    conn = get_connection()
    cursor = conn.cursor(as_dict=True)
    cursor.execute(query, params or ())
    row = cursor.fetchone()
    conn.close()
    return row

def execute_query(query, params=None):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(query, params or ())
    conn.commit()
    conn.close()