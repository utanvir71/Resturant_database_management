# Restaurant Big Data Management System

A Flask and Microsoft SQL Server based restaurant management system built for a university database project. The project models a multi-branch restaurant operation with customer reservations, staff-managed dining sessions, multi-item orders, payments, feedback, admin management, SQL stored procedures, and analytics exports for pandas and PySpark.

The main goal of this project is to demonstrate database design and SQL concepts in a realistic business workflow, not just simple CRUD pages. The application connects a normalized relational schema to a working web interface so that each major database operation can be tested through the app.

## Project Objective

This system is designed to manage restaurant operations across multiple branches.

It supports:

- Customers making reservations and viewing menu items.
- Staff confirming reservations, opening dining sessions, taking orders, recording payments, and closing sessions.
- Admins managing menu items, staff, shifts, and analytics.
- SQL Server enforcing important business rules through constraints and stored procedures.
- CSV export and offline analytics with pandas and PySpark.

The project is useful for demonstrating:

- Relational database schema design.
- Primary keys and foreign keys.
- Many-to-many relationships.
- Check constraints.
- Joins.
- Subqueries.
- Common Table Expressions.
- Window functions.
- Views.
- Stored procedures.
- Triggers.
- Indexes.
- Flask integration with SQL Server.
- Analytics using SQL aggregates, pandas, and PySpark.

## Tech Stack

- Backend: Python, Flask
- Database: Microsoft SQL Server
- Database driver: pymssql
- Frontend: HTML, Jinja templates, CSS
- Environment variables: python-dotenv
- Analytics: SQL aggregates, pandas, PySpark
- Optional big data environment: Databricks or local PySpark

## Main Roles

The application has three user flows.

### Customer

Customer access is intentionally simple because this is a university project. A customer can continue from the login page without a password.

Customer features:

- View dashboard.
- Browse branch menu items.
- Make a reservation.
- View reservation history.
- Submit feedback for dining sessions.

### Staff

Staff login uses phone number plus a shared staff password. Staff accounts must be active. Staff members are limited to their assigned branch.

Staff features:

- View staff dashboard.
- Manage reservations for their branch.
- Confirm, cancel, or mark confirmed reservations as no-show.
- Open dining sessions from confirmed reservations.
- Open walk-in dining sessions.
- View active dining sessions.
- Take orders with multiple menu items.
- View order details.
- Update order status.
- Record payment.
- Close dining sessions after all active orders are paid or cancelled.

### Admin

Admin login uses a shared admin password. This is kept simple for project demonstration.

Admin features:

- View admin dashboard.
- View reservations.
- Add menu items.
- Update menu price and availability.
- Add staff.
- Update staff status.
- Add shifts.
- Update shift status.
- View analytics dashboard.
- Export analytics datasets as CSV.

## Authentication Design

This project does not implement production-level authentication because the focus is database design and application workflow.

Default values are loaded from `config.py` and can be overridden in `.env`.

Environment variables:

```env
SECRET_KEY=your-secret-key
ADMIN_PASSWORD=admin123
STAFF_PASSWORD=staff123
DB_SERVER=localhost
DB_DATABASE=rdb_3
DB_USERNAME=sa
DB_PASSWORD=your-sql-server-password
DB_PORT=1433
```

Important notes:

- Customer login is button-based.
- Admin login uses one shared admin password.
- Staff login uses phone number plus one shared staff password.
- Staff pages filter data by the staff member's branch.
- Inactive staff cannot log in.

## Database Design

The main schema is in:

```text
sql/01_create_table.sql
```

The database contains the following main tables:

### Branch and Layout Tables

- `Branches`
- `Dining_Areas`
- `Restaurant_Tables`

These tables model restaurant branches, areas inside each branch, and tables inside each area.

Important rules:

- Branch opening time must be earlier than closing time.
- Dining area type is limited to valid values.
- Table capacity must be positive.
- Table status is controlled using values like `Available`, `Reserved`, `Occupied`, and `Maintenance`.

### Customer and Staff Tables

- `Customers`
- `Staff_Roles`
- `Staff`
- `Shifts`

These tables store customers, staff roles, staff members, and staff shift schedules.

Important rules:

- Customer phone and email are unique.
- Staff phone is unique.
- Staff salary cannot be negative.
- Staff status must be `Active`, `Inactive`, or `OnLeave`.
- Shift start time must be before end time.
- Shift status must be `Scheduled`, `Completed`, or `Cancelled`.

### Menu Tables

- `Menu_Categories`
- `Menu_Items`
- `Branch_Menu_Items`

The menu is separated into global item information and branch-specific price or availability.

This allows the same menu item to exist at different branches with different prices or availability.

Important rules:

- Menu item calories cannot be negative.
- Branch menu item price cannot be negative.
- Availability is either `Available` or `Unavailable`.

### Reservation and Dining Tables

- `Reservations`
- `Dining_Sessions`

Reservations are planned customer visits. Dining sessions represent actual seated customers.

The system supports:

- Reservation customers.
- Walk-in customers.
- Confirmed reservations becoming dining sessions.
- One dining session having multiple orders.

Reservation statuses:

- `Pending`
- `Confirmed`
- `Cancelled`
- `NoShow`
- `Completed`

Dining session statuses:

- `Open`
- `Closed`

### Order and Payment Tables

- `Orders`
- `Order_Items`
- `Payments`
- `Promotions`
- `Order_Promotions`

Orders are connected to dining sessions. One order can contain multiple menu items through `Order_Items`.

Important design choices:

- One dining session can have multiple orders.
- One order can have multiple menu items.
- Each order is paid separately.
- One payment is recorded per order.
- `Order_Items.agreed_unit_price` stores the price at the time of ordering, so later menu price changes do not change historical order totals.
- `Order_Promotions` supports multiple promotions per order.

Order statuses:

- `Placed`
- `Preparing`
- `Served`
- `Cancelled`

Payment statuses:

- `Paid`
- `Refunded`
- `Failed`

Payment methods:

- `Cash`
- `Card`
- `MobilePayment`

### Feedback Table

- `Feedback`

Feedback is linked to dining sessions and stores ratings between 1 and 5.

## Business Workflow

### Reservation Workflow

1. Customer creates reservation.
2. Reservation starts as `Pending`.
3. Staff confirms reservation.
4. Confirmed reservation marks the table as `Reserved`.
5. Staff opens dining session when the customer arrives.
6. Open dining session marks the table as `Occupied`.
7. Staff closes session after all active orders are paid or cancelled.
8. Closed session releases the table back to `Available`.
9. Linked reservation becomes `Completed`.

### Walk-In Workflow

1. Staff enters walk-in customer name and phone.
2. System finds existing customer by phone or creates a new customer.
3. Staff selects an available table in their branch.
4. Dining session opens without a reservation.
5. Table becomes `Occupied`.

### Order Workflow

1. Staff selects an open dining session.
2. Staff adds one or more menu items.
3. SQL Server creates one order and multiple order item rows in one transaction.
4. Order starts as `Placed`.
5. Staff can mark it as `Preparing`.
6. Staff can mark it as `Served`.
7. Staff records payment.
8. Payment amount is calculated from `Order_Items`.

### Session Closing Workflow

1. Staff clicks close session.
2. Stored procedure checks the session belongs to the staff branch.
3. Stored procedure checks session is open.
4. Stored procedure checks every non-cancelled order has a paid payment.
5. Session becomes `Closed`.
6. Table becomes `Available`.
7. Linked reservation becomes `Completed`.

## Stored Procedures

Stored procedures are stored in:

```text
sql/11_stored_procedure.sql
```

Implemented procedures:

- `sp_UpdateReservationStatus`
- `sp_SyncTableStatuses`
- `sp_OpenDiningSessionFromReservation`
- `sp_OpenWalkInDiningSession`
- `sp_CreateOrderWithItems`
- `sp_UpdateOrderStatus`
- `sp_RecordOrderPayment`
- `sp_CloseDiningSession`
- `sp_AdminAddMenuItem`
- `sp_AdminUpdateBranchMenuItem`
- `sp_AdminAddStaff`
- `sp_AdminUpdateStaffStatus`
- `sp_AdminAddShift`
- `sp_AdminUpdateShiftStatus`

Why stored procedures are used:

- To keep important business rules inside the database.
- To make multi-table changes inside transactions.
- To reduce duplicate validation logic in Flask.
- To show SQL Server procedural programming.
- To demonstrate `RAISERROR`, `BEGIN TRANSACTION`, `COMMIT TRANSACTION`, `SCOPE_IDENTITY`, `OPENJSON`, and branch ownership checks.

Example: `sp_CreateOrderWithItems`

- Accepts a dining session id, staff id, staff branch id, and JSON item list.
- Validates the session is open.
- Validates staff belongs to the branch and is active.
- Validates selected menu items are available at that branch.
- Inserts one row into `Orders`.
- Inserts multiple rows into `Order_Items`.
- Copies current branch price into `agreed_unit_price`.

## SQL Concept Files

The `sql` folder contains separate scripts to demonstrate different database concepts:

```text
sql/01_create_table.sql
sql/02_seed_data.sql
sql/03_queries.sql
sql/04_join.sql
sql/05_select_update.sql
sql/06_conditional.sql
sql/07_subqueries.sql
sql/08_cte.sql
sql/09_window_function.sql
sql/10_view.sql
sql/11_stored_procedure.sql
sql/12_triggers.sql
sql/13_index.sql
```

Recommended execution order for a fresh database:

1. `01_create_table.sql`
2. `02_seed_data.sql`
3. `10_view.sql`
4. `11_stored_procedure.sql`
5. `12_triggers.sql`
6. `13_index.sql`

The other files are useful for professor review because they show standalone examples of joins, updates, conditionals, subqueries, CTEs, and window functions.

## Flask Application Structure

Main files:

```text
app.py
config.py
db.py
requirements.txt
static/css/style.css
templates/
sql/
anaytics/
exports/
```

### `app.py`

Contains all Flask routes and page logic.

Main route groups:

- `/` login page
- `/login/customer`
- `/login/admin`
- `/login/staff`
- `/admin/dashboard`
- `/admin/reservations`
- `/admin/menu`
- `/admin/staff`
- `/admin/shifts`
- `/admin/analytics`
- `/customer/dashboard`
- `/customer/make_reservation`
- `/customer/reservations`
- `/customer/menu`
- `/customer/feedback`
- `/staff/dashboard`
- `/staff/reservations`
- `/staff/open_session`
- `/staff/active_sessions`
- `/staff/take_order`
- `/staff/orders`

### `db.py`

Contains helper functions:

- `get_connection()`
- `fetch_all()`
- `fetch_one()`
- `execute_query()`

These functions connect Flask to SQL Server using `pymssql`.

### `config.py`

Loads configuration from environment variables using `python-dotenv`.

### `templates/`

Contains Jinja templates for:

- Admin pages
- Staff pages
- Customer pages
- Shared base layout

### `static/`

Contains CSS and JavaScript assets.

## Analytics

The project includes three analytics layers.

### 1. SQL Analytics Dashboard

The admin analytics dashboard is available at:

```text
/admin/analytics
```

It shows:

- Total revenue
- Paid orders
- Closed sessions
- Average feedback rating
- Revenue by branch
- Payment method totals
- Top selling menu items
- Reservation status counts
- Dining session status counts
- Feedback by branch

These values are calculated using SQL joins, grouping, and aggregate functions.

### 2. CSV Export

The analytics page can export datasets as CSV:

- Orders
- Order items
- Payments
- Reservations
- Feedback

Export routes:

```text
/admin/analytics/export/orders
/admin/analytics/export/order_items
/admin/analytics/export/payments
/admin/analytics/export/reservations
/admin/analytics/export/feedback
```

These exports are useful for Excel, pandas, PySpark, or Databricks.

### 3. pandas Analytics

Local pandas script:

```text
anaytics/pandas_analystics.py
```

Run example:

```bash
python anaytics/pandas_analystics.py --source-dir ~/Downloads
```

It creates summary CSV files in:

```text
exports/
```

Generated summaries include:

- `branch_revenue_summary.csv`
- `payment_method_summary.csv`
- `menu_sales_summary.csv`
- `reservation_status_summary.csv`
- `feedback_summary.csv`

### 4. PySpark and Databricks Analytics

PySpark script:

```text
anaytics/pyspark_analystics.py
```

Run locally:

```bash
python anaytics/pyspark_analystics.py --source-dir ~/Downloads
```

It writes Spark output folders in:

```text
exports/spark_summaries/
```

This script demonstrates Spark operations:

- `SparkSession`
- `read.csv`
- `groupBy`
- `agg`
- `sum`
- `avg`
- `count`
- distributed CSV output

For Databricks, upload the exported CSV files and reuse the same PySpark grouping logic with Databricks file paths.

## Setup Instructions

### 1. Clone the repository

```bash
git clone https://github.com/utanvir71/Resturant_database_management.git
cd Resturant_database_management
```

### 2. Create and activate virtual environment

macOS or Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

Windows:

```bash
python -m venv .venv
.venv\Scripts\activate
```

### 3. Install dependencies

```bash
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### 4. Create `.env`

Create a `.env` file in the project root:

```env
SECRET_KEY=restaurant-demo-secret
ADMIN_PASSWORD=admin123
STAFF_PASSWORD=staff123
DB_SERVER=localhost
DB_DATABASE=rdb_3
DB_USERNAME=sa
DB_PASSWORD=your-sql-server-password
DB_PORT=1433
```

### 5. Start SQL Server

Start your SQL Server instance before running Flask.

If using Docker, make sure the SQL Server container is running and port `1433` is available.

### 6. Create and seed database

Open SQL Server Management Studio, Azure Data Studio, or another SQL client.

Run the SQL scripts from the `sql` folder in this order:

```text
01_create_table.sql
02_seed_data.sql
10_view.sql
11_stored_procedure.sql
12_triggers.sql
13_index.sql
```

### 7. Run Flask

```bash
python app.py
```

Open:

```text
http://localhost:8001
```

## Demo Guide

Recommended demo flow:

1. Start from login page.
2. Continue as customer.
3. Show customer menu.
4. Make a reservation.
5. Logout.
6. Login as staff.
7. Confirm the reservation.
8. Open a dining session.
9. Take an order with multiple menu items.
10. Open order details.
11. Mark order preparing or served.
12. Record payment.
13. Close dining session.
14. Logout.
15. Login as admin.
16. Show dashboard.
17. Manage menu item availability or price.
18. Add or update staff.
19. Add or update shift.
20. Open analytics dashboard.
21. Export CSV.
22. Run pandas or PySpark analytics script.

This flow demonstrates the full database workflow from reservation to analytics.

## Important Business Rules

- Staff can only manage reservations, sessions, and orders for their own branch.
- Pending reservations do not reserve a table yet.
- Confirmed reservations mark the table as reserved.
- Open dining sessions mark the table as occupied.
- Closed dining sessions release the table.
- Confirmed reservations cannot be opened twice.
- Walk-in sessions can only use available tables.
- Orders can only be created for open sessions.
- One order can contain multiple menu items.
- Paid orders cannot be cancelled.
- Cancelled orders cannot be paid.
- A session cannot close while it has unpaid active orders.
- Staff are soft-removed by changing status to `Inactive`.
- Menu items are safely removed from ordering by changing branch availability to `Unavailable`.
- Historical order prices do not change when menu prices are updated.

## Screenshots

Recommended screenshots to add for final presentation:

- Login page
- Admin dashboard
- Admin menu management
- Admin staff management
- Admin shifts page
- Admin analytics page
- Staff reservations page
- Open dining session page
- Take order page
- Order details page
- Customer reservation page
- Customer menu page

Place screenshots in a folder such as:

```text
static/screenshots/
```

Then link them in this README if required by the professor.

## Current Limitations

This project is designed for a university database course, so some production features are intentionally simplified.

Limitations:

- Authentication is simplified.
- Passwords are shared for admin and staff demonstration.
- Customer account management is minimal.
- No production deployment configuration is included.
- The UI is functional and project-focused rather than a commercial restaurant product.
- The folder name `anaytics` is misspelled but kept for compatibility with existing files.

## Future Improvements

Possible improvements:

- Rename `anaytics` to `analytics`.
- Add hashed passwords.
- Add customer registration.
- Add role-based admin users.
- Add automated tests.
- Add Docker Compose for Flask and SQL Server.
- Add chart visualizations to analytics.
- Add Databricks notebook version of the PySpark script.
- Add API endpoints for mobile or frontend clients.

## Project Status

The local application includes:

- Working role-based pages.
- SQL Server database connection.
- Stored procedure based business workflows.
- Admin menu, staff, shift, and analytics modules.
- Staff reservation, session, order, payment, and close-session modules.
- Customer reservation, menu, and feedback modules.
- pandas and PySpark analytics scripts.

The project is presentation-ready after the local working code is committed and pushed to GitHub.
