import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "supersecretkey")
    ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "admin123")
    STAFF_PASSWORD = os.getenv("STAFF_PASSWORD", "staff123")
    DB_SERVER = os.getenv("DB_SERVER", "localhost")
    DB_DATABASE = os.getenv("DB_DATABASE", "rdb_3")
    DB_USERNAME = os.getenv("DB_USERNAME", "sa")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_PORT = int(os.getenv("DB_PORT", 1433))
