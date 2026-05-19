from flask import Flask, render_template
from config import Config
from db import fetch_one

app = Flask(__name__)
app.config.from_object(Config)


@app.route("/")
def home():
    return render_template("login.html")


@app.route("/admin/dashboard")
def admin_dashboard():
    try:
        total_branches_row = fetch_one("SELECT COUNT(*) AS total FROM Branches")
        total_customers_row = fetch_one("SELECT COUNT(*) AS total FROM Customers")
        total_reservations_row = fetch_one("SELECT COUNT(*) AS total FROM Reservations")
        total_orders_row = fetch_one("SELECT COUNT(*) AS total FROM [Orders]")

        total_branches = total_branches_row["total"] if total_branches_row else 0
        total_customers = total_customers_row["total"] if total_customers_row else 0
        total_reservations = total_reservations_row["total"] if total_reservations_row else 0
        total_orders = total_orders_row["total"] if total_orders_row else 0

        return render_template(
            "admin/dashboard.html",
            total_branches=total_branches,
            total_customers=total_customers,
            total_reservations=total_reservations,
            total_orders=total_orders
        )
    except Exception as e:
        return f"<h1>Admin Dashboard Error</h1><pre>{str(e)}</pre>"


@app.route("/customer/dashboard")
def customer_dashboard():
    return render_template("customer/dashboard.html")


@app.route("/staff/dashboard")
def staff_dashboard():
    return render_template("staff/dashboard.html")


if __name__ == "__main__":
    app.run(debug=True, port=8001)