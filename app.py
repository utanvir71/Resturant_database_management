from datetime import datetime
from functools import wraps

from flask import Flask, redirect, render_template, request, session, url_for
from config import Config
from db import execute_query, fetch_all, fetch_one

app = Flask(__name__)
app.config.from_object(Config)


def require_role(role):
    def decorator(view_func):
        @wraps(view_func)
        def wrapped_view(*args, **kwargs):
            if session.get("role") != role:
                return redirect(url_for("home", next=request.path))
            return view_func(*args, **kwargs)
        return wrapped_view
    return decorator


def current_staff_branch_id():
    branch_id = session.get("staff_branch_id")
    return int(branch_id) if branch_id else None


def safe_redirect_target(next_url, fallback_endpoint):
    if next_url and next_url.startswith("/") and not next_url.startswith("//"):
        return next_url
    return url_for(fallback_endpoint)


def get_available_tables():
    return fetch_all("""
        SELECT
            rt.table_id,
            rt.table_number,
            rt.capacity,
            rt.table_status,
            da.area_name,
            b.branch_id,
            b.branch_name
        FROM Restaurant_Tables rt
        JOIN Dining_Areas da ON rt.area_id = da.area_id
        JOIN Branches b ON da.branch_id = b.branch_id
        WHERE rt.table_status = 'Available'
        ORDER BY b.branch_name, rt.capacity, rt.table_number
    """)


def get_branches():
    return fetch_all("""
        SELECT branch_id, branch_name, location
        FROM Branches
        ORDER BY branch_name
    """)


def load_make_reservation_context(error=None, form_data=None):
    return {
        "branches": get_branches(),
        "tables": get_available_tables(),
        "error": error,
        "form_data": form_data or {},
    }


@app.route("/")
def home():
    return render_template(
        "login.html",
        error=request.args.get("error"),
        next_url=request.args.get("next", "")
    )


@app.route("/login/customer")
def login_customer():
    session.clear()
    session["role"] = "customer"
    return redirect(url_for("customer_dashboard"))


@app.route("/login/admin", methods=["POST"])
def login_admin():
    password = request.form.get("password", "")

    if password != app.config["ADMIN_PASSWORD"]:
        return render_template(
            "login.html",
            error="Invalid admin password.",
            next_url=request.form.get("next_url", "")
        )

    session.clear()
    session["role"] = "admin"
    session["admin_name"] = "System Admin"
    return redirect(safe_redirect_target(request.form.get("next_url", ""), "admin_dashboard"))


@app.route("/login/staff", methods=["POST"])
def login_staff():
    phone = request.form.get("phone", "").strip()
    password = request.form.get("password", "")

    if password != app.config["STAFF_PASSWORD"]:
        return render_template(
            "login.html",
            error="Invalid staff phone or password.",
            next_url=request.form.get("next_url", "")
        )

    staff = fetch_one("""
        SELECT
            s.staff_id,
            s.branch_id,
            s.full_name,
            s.phone,
            b.branch_name
        FROM Staff s
        JOIN Branches b ON s.branch_id = b.branch_id
        WHERE s.phone = %s
          AND s.staff_status = 'Active'
    """, (phone,))

    if not staff:
        return render_template(
            "login.html",
            error="Invalid staff phone or inactive staff account.",
            next_url=request.form.get("next_url", "")
        )

    session.clear()
    session["role"] = "staff"
    session["staff_id"] = staff["staff_id"]
    session["staff_name"] = staff["full_name"]
    session["staff_branch_id"] = staff["branch_id"]
    session["staff_branch_name"] = staff["branch_name"]
    return redirect(safe_redirect_target(request.form.get("next_url", ""), "staff_dashboard"))


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("home"))


@app.route("/admin/dashboard")
@require_role("admin")
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


@app.route("/admin/reservations")
@require_role("admin")
def admin_reservations():
    try:
        selected_branch = request.args.get("branch", "")
        selected_status = request.args.get("status", "")
        selected_keyword = request.args.get("keyword", "").strip()

        branches = get_branches()

        query = """
        SELECT
            r.reservation_id,
            c.full_name AS customer_name,
            b.branch_name,
            rt.table_number,
            r.reservation_datetime,
            r.party_size,
            r.reservation_status,
            r.special_request
        FROM Reservations r
        JOIN Customers c ON r.customer_id = c.customer_id
        JOIN Restaurant_Tables rt ON r.table_id = rt.table_id
        JOIN Dining_Areas da ON rt.area_id = da.area_id
        JOIN Branches b ON da.branch_id = b.branch_id
        WHERE 1=1
        """

        params = []

        if selected_branch != "":
            query += " AND b.branch_id = %s"
            params.append(int(selected_branch))

        if selected_status != "":
            query += " AND r.reservation_status = %s"
            params.append(selected_status)

        if selected_keyword != "":
            query += """
            AND (
                c.full_name LIKE %s
                OR r.special_request LIKE %s
            )
            """
            keyword_param = f"%{selected_keyword}%"
            params.extend([keyword_param, keyword_param])

        query += " ORDER BY r.reservation_datetime DESC"

        reservations = fetch_all(query, tuple(params))

        return render_template(
            "admin/reservations.html",
            reservations=reservations,
            branches=branches,
            selected_branch=str(selected_branch),
            selected_status=selected_status,
            selected_keyword=selected_keyword
        )
    except Exception as e:
        return f"<h1>Reservations Page Error</h1><pre>{str(e)}</pre>"


@app.route("/customer/dashboard")
@require_role("customer")
def customer_dashboard():
    try:
        total_branches_row = fetch_one("SELECT COUNT(*) AS total FROM Branches")
        available_tables_row = fetch_one("""
            SELECT COUNT(*) AS total
            FROM Restaurant_Tables
            WHERE table_status = 'Available'
        """)
        upcoming_reservations_row = fetch_one("""
            SELECT COUNT(*) AS total
            FROM Reservations
            WHERE reservation_datetime >= GETDATE()
              AND reservation_status IN ('Pending', 'Confirmed')
        """)
        menu_items_row = fetch_one("""
            SELECT COUNT(*) AS total
            FROM Branch_Menu_Items
            WHERE availability_status = 'Available'
        """)

        return render_template(
            "customer/dashboard.html",
            total_branches=total_branches_row["total"] if total_branches_row else 0,
            available_tables=available_tables_row["total"] if available_tables_row else 0,
            upcoming_reservations=upcoming_reservations_row["total"] if upcoming_reservations_row else 0,
            menu_items=menu_items_row["total"] if menu_items_row else 0,
            customer_phone=session.get("customer_phone", "")
        )
    except Exception as e:
        return f"<h1>Customer Dashboard Error</h1><pre>{str(e)}</pre>"


@app.route("/customer/make_reservation", methods=["GET", "POST"])
@require_role("customer")
def customer_make_reservation():
    if request.method == "GET":
        try:
            return render_template(
                "customer/make_reservation.html",
                **load_make_reservation_context()
            )
        except Exception as e:
            return f"<h1>Make Reservation Page Error</h1><pre>{str(e)}</pre>"

    form_data = request.form.to_dict()
    form_data.setdefault("reservation_datetime", request.form.get("reservation_datetime", ""))

    try:
        full_name = request.form.get("full_name", "").strip()
        phone = request.form.get("phone", "").strip()
        email = request.form.get("email", "").strip() or None
        branch_id = int(request.form.get("branch_id", ""))
        table_id = int(request.form.get("table_id", ""))
        reservation_datetime_raw = request.form.get("reservation_datetime", "").strip()
        reservation_datetime = datetime.strptime(
            reservation_datetime_raw,
            "%Y-%m-%dT%H:%M"
        )
        reservation_datetime_sql = reservation_datetime.strftime("%Y-%m-%d %H:%M:%S")
        party_size = int(request.form.get("party_size", ""))
        special_request = request.form.get("special_request", "").strip() or None

        if not full_name or not phone:
            raise ValueError("Full name and phone number are required.")

        if party_size < 1:
            raise ValueError("Party size must be at least 1.")

        table = fetch_one("""
            SELECT
                rt.table_id,
                rt.capacity,
                rt.table_status,
                b.branch_id,
                b.branch_name,
                rt.table_number
            FROM Restaurant_Tables rt
            JOIN Dining_Areas da ON rt.area_id = da.area_id
            JOIN Branches b ON da.branch_id = b.branch_id
            WHERE rt.table_id = %s
              AND b.branch_id = %s
        """, (table_id, branch_id))

        if not table:
            raise ValueError("Please choose an available table from the selected branch.")

        if table["table_status"] != "Available":
            raise ValueError(
                f"Table {table['table_number']} at {table['branch_name']} is currently marked as {table['table_status']}."
            )

        if party_size > table["capacity"]:
            raise ValueError("Party size cannot be greater than the selected table capacity.")

        customer = fetch_one("""
            SELECT customer_id
            FROM Customers
            WHERE phone = %s
        """, (phone,))

        if not customer:
            execute_query("""
                INSERT INTO Customers (full_name, phone, email)
                VALUES (%s, %s, %s)
            """, (full_name, phone, email))

            customer = fetch_one("""
                SELECT customer_id
                FROM Customers
                WHERE phone = %s
            """, (phone,))

        conflicting_reservation = fetch_one("""
            SELECT reservation_id
            FROM Reservations
            WHERE table_id = %s
              AND CAST(reservation_datetime AS DATETIME) = CAST(%s AS DATETIME)
              AND reservation_status IN ('Pending', 'Confirmed')
        """, (table_id, reservation_datetime_sql))

        if conflicting_reservation:
            raise ValueError("This table is already reserved at the selected time.")

        execute_query("""
            INSERT INTO Reservations (
                customer_id,
                table_id,
                reservation_datetime,
                party_size,
                reservation_status,
                special_request
            )
            VALUES (%s, %s, CAST(%s AS DATETIME), %s, 'Pending', %s)
        """, (
            customer["customer_id"],
            table_id,
            reservation_datetime_sql,
            party_size,
            special_request
        ))

        inserted_reservation = fetch_one("""
            SELECT TOP 1 reservation_id
            FROM Reservations
            WHERE customer_id = %s
              AND table_id = %s
              AND CAST(reservation_datetime AS DATETIME) = CAST(%s AS DATETIME)
            ORDER BY reservation_id DESC
        """, (
            customer["customer_id"],
            table_id,
            reservation_datetime_sql
        ))

        if not inserted_reservation:
            raise ValueError("Reservation insert did not complete. Please try again.")

        session["customer_phone"] = phone
        return redirect(url_for("customer_reservations", success="1"))
    except ValueError as e:
        return render_template(
            "customer/make_reservation.html",
            **load_make_reservation_context(error=str(e), form_data=form_data)
        )
    except Exception as e:
        return render_template(
            "customer/make_reservation.html",
            **load_make_reservation_context(
                error=f"Unexpected error while saving reservation: {str(e)}",
                form_data=form_data
            )
        )


@app.route("/customer/reservations")
@require_role("customer")
def customer_reservations():
    try:
        requested_phone = request.args.get("phone")
        if requested_phone is None:
            phone = session.get("customer_phone", "")
        else:
            phone = requested_phone.strip()
            if not phone:
                session.pop("customer_phone", None)

        reservations = []

        if phone:
            reservations = fetch_all("""
                SELECT
                    r.reservation_id,
                    c.full_name AS customer_name,
                    c.phone,
                    b.branch_name,
                    rt.table_number,
                    rt.capacity,
                    r.reservation_datetime,
                    r.party_size,
                    r.reservation_status,
                    r.special_request
                FROM Reservations r
                JOIN Customers c ON r.customer_id = c.customer_id
                JOIN Restaurant_Tables rt ON r.table_id = rt.table_id
                JOIN Dining_Areas da ON rt.area_id = da.area_id
                JOIN Branches b ON da.branch_id = b.branch_id
                WHERE c.phone = %s
                ORDER BY r.reservation_datetime DESC
            """, (phone,))

        return render_template(
            "customer/reservations.html",
            reservations=reservations,
            phone=phone,
            success=request.args.get("success") == "1"
        )
    except Exception as e:
        return f"<h1>Customer Reservations Error</h1><pre>{str(e)}</pre>"


@app.route("/customer/menu")
@require_role("customer")
def customer_menu():
    try:
        selected_branch = request.args.get("branch", "")
        branches = get_branches()

        query = """
        SELECT
            b.branch_name,
            mc.category_name,
            mi.item_name,
            mi.description,
            mi.calories,
            bmi.price,
            bmi.availability_status
        FROM Branch_Menu_Items bmi
        JOIN Branches b ON bmi.branch_id = b.branch_id
        JOIN Menu_Items mi ON bmi.item_id = mi.item_id
        JOIN Menu_Categories mc ON mi.category_id = mc.category_id
        WHERE 1=1
        """
        params = []

        if selected_branch:
            query += " AND b.branch_id = %s"
            params.append(int(selected_branch))

        query += """
        ORDER BY b.branch_name, mc.category_name, mi.item_name
        """

        menu_items = fetch_all(query, tuple(params))

        return render_template(
            "customer/menu.html",
            branches=branches,
            menu_items=menu_items,
            selected_branch=str(selected_branch)
        )
    except Exception as e:
        return f"<h1>Customer Menu Error</h1><pre>{str(e)}</pre>"


def get_feedback_sessions(phone=None):
    query = """
    SELECT TOP 50
        ds.session_id,
        ds.session_start,
        c.full_name AS customer_name,
        c.phone,
        b.branch_name,
        rt.table_number
    FROM Dining_Sessions ds
    JOIN Customers c ON ds.customer_id = c.customer_id
    JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
    JOIN Dining_Areas da ON rt.area_id = da.area_id
    JOIN Branches b ON da.branch_id = b.branch_id
    LEFT JOIN Feedback f ON ds.session_id = f.session_id
    WHERE ds.session_status = 'Closed'
      AND f.feedback_id IS NULL
    """
    params = []

    if phone:
        query += " AND c.phone = %s"
        params.append(phone)

    query += " ORDER BY ds.session_start DESC"
    return fetch_all(query, tuple(params))


@app.route("/customer/feedback", methods=["GET", "POST"])
@require_role("customer")
def customer_feedback():
    requested_phone = request.args.get("phone")
    phone = requested_phone.strip() if requested_phone is not None else session.get("customer_phone", "")

    if request.method == "GET":
        try:
            return render_template(
                "customer/feedback.html",
                sessions=get_feedback_sessions(phone),
                phone=phone,
                success=request.args.get("success") == "1",
                error=None,
                form_data={}
            )
        except Exception as e:
            return f"<h1>Customer Feedback Error</h1><pre>{str(e)}</pre>"

    form_data = request.form.to_dict()

    try:
        session_id = int(request.form.get("session_id", ""))
        rating = int(request.form.get("rating", ""))
        comments = request.form.get("comments", "").strip() or None

        if rating < 1 or rating > 5:
            raise ValueError("Rating must be between 1 and 5.")

        dining_session = fetch_one("""
            SELECT session_id
            FROM Dining_Sessions
            WHERE session_id = %s
        """, (session_id,))

        if not dining_session:
            raise ValueError("Please select a valid dining session.")

        existing_feedback = fetch_one("""
            SELECT feedback_id
            FROM Feedback
            WHERE session_id = %s
        """, (session_id,))

        if existing_feedback:
            raise ValueError("Feedback has already been submitted for this dining session.")

        execute_query("""
            INSERT INTO Feedback (session_id, rating, comments)
            VALUES (%s, %s, %s)
        """, (session_id, rating, comments))

        return redirect(url_for("customer_feedback", phone=phone, success="1"))
    except ValueError as e:
        return render_template(
            "customer/feedback.html",
            sessions=get_feedback_sessions(phone),
            phone=phone,
            success=False,
            error=str(e),
            form_data=form_data
        )
    except Exception as e:
        return f"<h1>Customer Feedback Submit Error</h1><pre>{str(e)}</pre>"


@app.route("/staff/dashboard")
@require_role("staff")
def staff_dashboard():
    try:
        branch_id = current_staff_branch_id()

        open_sessions_row = fetch_one("""
            SELECT COUNT(*) AS total
            FROM Dining_Sessions ds
            JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
            JOIN Dining_Areas da ON rt.area_id = da.area_id
            WHERE ds.session_status = 'Open'
              AND da.branch_id = %s
        """, (branch_id,))
        active_staff_row = fetch_one("""
            SELECT COUNT(*) AS total
            FROM Staff
            WHERE staff_status = 'Active'
              AND branch_id = %s
        """, (branch_id,))
        pending_orders_row = fetch_one("""
            SELECT COUNT(*) AS total
            FROM [Orders] o
            JOIN Dining_Sessions ds ON o.session_id = ds.session_id
            JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
            JOIN Dining_Areas da ON rt.area_id = da.area_id
            WHERE o.order_status IN ('Placed', 'Preparing')
              AND da.branch_id = %s
        """, (branch_id,))
        served_orders_row = fetch_one("""
            SELECT COUNT(*) AS total
            FROM [Orders] o
            JOIN Dining_Sessions ds ON o.session_id = ds.session_id
            JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
            JOIN Dining_Areas da ON rt.area_id = da.area_id
            WHERE o.order_status = 'Served'
              AND da.branch_id = %s
        """, (branch_id,))
        branch_activity = fetch_all("""
            SELECT
                b.branch_name,
                COUNT(o.order_id) AS total_orders
            FROM Branches b
            LEFT JOIN Staff s ON b.branch_id = s.branch_id
            LEFT JOIN [Orders] o ON s.staff_id = o.staff_id
            WHERE b.branch_id = %s
            GROUP BY b.branch_name
            ORDER BY total_orders DESC, b.branch_name
        """, (branch_id,))
        active_session_branch_activity = fetch_all("""
            SELECT
                b.branch_name,
                COUNT(ds.session_id) AS total_open_sessions
            FROM Branches b
            LEFT JOIN Dining_Areas da ON b.branch_id = da.branch_id
            LEFT JOIN Restaurant_Tables rt ON da.area_id = rt.area_id
            LEFT JOIN Dining_Sessions ds
                ON rt.table_id = ds.table_id
               AND ds.session_status = 'Open'
            WHERE b.branch_id = %s
            GROUP BY b.branch_name
        """, (branch_id,))
        recent_active_sessions = fetch_all("""
            SELECT TOP 6
                ds.session_id,
                c.full_name AS customer_name,
                b.branch_name,
                rt.table_number,
                ds.session_start,
                ds.session_status
            FROM Dining_Sessions ds
            JOIN Customers c ON ds.customer_id = c.customer_id
            JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
            JOIN Dining_Areas da ON rt.area_id = da.area_id
            JOIN Branches b ON da.branch_id = b.branch_id
            WHERE ds.session_status = 'Open'
              AND b.branch_id = %s
            ORDER BY ds.session_start DESC
        """, (branch_id,))
        recent_orders = fetch_all("""
            SELECT TOP 6
                o.order_id,
                o.order_datetime,
                o.order_status,
                b.branch_name,
                rt.table_number,
                s.full_name AS staff_name
            FROM [Orders] o
            JOIN Dining_Sessions ds ON o.session_id = ds.session_id
            JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
            JOIN Dining_Areas da ON rt.area_id = da.area_id
            JOIN Branches b ON da.branch_id = b.branch_id
            JOIN Staff s ON o.staff_id = s.staff_id
            WHERE b.branch_id = %s
            ORDER BY o.order_datetime DESC
        """, (branch_id,))

        return render_template(
            "staff/dashboard.html",
            open_sessions=open_sessions_row["total"] if open_sessions_row else 0,
            active_staff=active_staff_row["total"] if active_staff_row else 0,
            pending_orders=pending_orders_row["total"] if pending_orders_row else 0,
            served_orders=served_orders_row["total"] if served_orders_row else 0,
            branch_activity=branch_activity,
            recent_orders=recent_orders,
            recent_active_sessions=recent_active_sessions,
            active_session_branch_activity=active_session_branch_activity
        )
    except Exception as e:
        return f"<h1>Staff Dashboard Error</h1><pre>{str(e)}</pre>"


@app.route("/staff/orders")
@require_role("staff")
def staff_orders():
    try:
        branch_id = current_staff_branch_id()
        selected_status = request.args.get("status", "")

        statuses = fetch_all("""
            SELECT DISTINCT order_status
            FROM [Orders]
            ORDER BY order_status
        """)

        query = """
        SELECT
            o.order_id,
            o.order_datetime,
            o.order_status,
            ds.session_status,
            c.full_name AS customer_name,
            b.branch_name,
            rt.table_number,
            s.full_name AS staff_name,
            COUNT(oi.order_item_id) AS item_count,
            COALESCE(SUM(oi.quantity * oi.agreed_unit_price), 0) AS total_amount
        FROM [Orders] o
        JOIN Dining_Sessions ds ON o.session_id = ds.session_id
        JOIN Customers c ON ds.customer_id = c.customer_id
        JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
        JOIN Dining_Areas da ON rt.area_id = da.area_id
        JOIN Branches b ON da.branch_id = b.branch_id
        JOIN Staff s ON o.staff_id = s.staff_id
        LEFT JOIN Order_Items oi ON o.order_id = oi.order_id
        WHERE b.branch_id = %s
        """
        params = [branch_id]

        if selected_status:
            query += " AND o.order_status = %s"
            params.append(selected_status)

        query += """
        GROUP BY
            o.order_id,
            o.order_datetime,
            o.order_status,
            ds.session_status,
            c.full_name,
            b.branch_name,
            rt.table_number,
            s.full_name
        ORDER BY o.order_datetime DESC
        """

        orders = fetch_all(query, tuple(params))

        return render_template(
            "staff/orders.html",
            orders=orders,
            statuses=statuses,
            selected_status=selected_status
        )
    except Exception as e:
        return f"<h1>Staff Orders Error</h1><pre>{str(e)}</pre>"

@app.route("/staff/active_sessions")
@require_role("staff")
def staff_active_sessions():
    try:
        branch_id = current_staff_branch_id()
        active_sessions = fetch_all("""
            SELECT
                ds.session_id,
                c.full_name AS customer_name,
                b.branch_name,
                da.area_name,
                rt.table_number,
                ds.reservation_id,
                ds.session_start,
                ds.session_status
            FROM Dining_Sessions ds
            JOIN Customers c
                ON ds.customer_id = c.customer_id
            JOIN Restaurant_Tables rt
                ON ds.table_id = rt.table_id
            JOIN Dining_Areas da
                ON rt.area_id = da.area_id
            JOIN Branches b
                ON da.branch_id = b.branch_id
            WHERE ds.session_status = 'Open'
              AND b.branch_id = %s
            ORDER BY ds.session_start DESC
        """, (branch_id,))

        return render_template(
            "staff/active_sessions.html",
            active_sessions=active_sessions
        )
    except Exception as e:
        return f"<h1>Active Sessions Page Error</h1><pre>{str(e)}</pre>"

if __name__ == "__main__":
    app.run(debug=True, port=8001)
