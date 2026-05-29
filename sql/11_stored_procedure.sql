USE rdb_3;
GO

/* ============================================================
   Stored Procedure: Update Reservation Status
   Purpose:
   - Enforce staff branch ownership for reservation updates.
   - Control valid reservation status transitions.
   - Keep Restaurant_Tables.table_status aligned with reservation status.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_UpdateReservationStatus
    @reservation_id INT,
    @staff_branch_id INT,
    @new_status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @current_status VARCHAR(20),
        @table_id INT,
        @table_status VARCHAR(20),
        @reservation_branch_id INT,
        @reservation_datetime DATETIME;

    SELECT
        @current_status = r.reservation_status,
        @table_id = r.table_id,
        @table_status = rt.table_status,
        @reservation_branch_id = da.branch_id,
        @reservation_datetime = r.reservation_datetime
    FROM Reservations r
    JOIN Restaurant_Tables rt ON r.table_id = rt.table_id
    JOIN Dining_Areas da ON rt.area_id = da.area_id
    WHERE r.reservation_id = @reservation_id;

    IF @current_status IS NULL
    BEGIN
        RAISERROR('Reservation not found.', 16, 1);
        RETURN;
    END;

    IF @reservation_branch_id <> @staff_branch_id
    BEGIN
        RAISERROR('This reservation does not belong to the staff member''s branch.', 16, 1);
        RETURN;
    END;

    IF @new_status NOT IN ('Confirmed', 'Cancelled', 'NoShow')
    BEGIN
        RAISERROR('Invalid reservation status for staff update.', 16, 1);
        RETURN;
    END;

    IF @current_status IN ('Completed', 'Cancelled', 'NoShow')
    BEGIN
        RAISERROR('Finalized reservations cannot be changed from the staff reservation page.', 16, 1);
        RETURN;
    END;

    IF @new_status = 'Confirmed' AND @current_status <> 'Pending'
    BEGIN
        RAISERROR('Only pending reservations can be confirmed.', 16, 1);
        RETURN;
    END;

    IF @new_status = 'Cancelled' AND @current_status NOT IN ('Pending', 'Confirmed')
    BEGIN
        RAISERROR('Only pending or confirmed reservations can be cancelled.', 16, 1);
        RETURN;
    END;

    IF @new_status = 'NoShow' AND @current_status <> 'Confirmed'
    BEGIN
        RAISERROR('Only confirmed reservations can be marked as no-show.', 16, 1);
        RETURN;
    END;

    IF @new_status = 'Confirmed'
    BEGIN
        IF @table_status NOT IN ('Available', 'Reserved')
        BEGIN
            RAISERROR('The selected table is not available for confirmation.', 16, 1);
            RETURN;
        END;

        IF EXISTS (
            SELECT 1
            FROM Reservations
            WHERE reservation_id <> @reservation_id
              AND table_id = @table_id
              AND reservation_datetime = @reservation_datetime
              AND reservation_status = 'Confirmed'
        )
        BEGIN
            RAISERROR('Another confirmed reservation already exists for this table and time.', 16, 1);
            RETURN;
        END;
    END;

    BEGIN TRANSACTION;

    UPDATE Reservations
    SET reservation_status = @new_status
    WHERE reservation_id = @reservation_id;

    UPDATE Restaurant_Tables
    SET table_status =
        CASE
            WHEN @new_status = 'Confirmed' THEN 'Reserved'
            WHEN @new_status IN ('Cancelled', 'NoShow') THEN 'Available'
            ELSE table_status
        END
    WHERE table_id = @table_id;

COMMIT TRANSACTION;
END;
GO

/* ============================================================
   Stored Procedure: Sync Table Statuses
   Purpose:
   - Repair table_status values after seed data or manual SQL changes.
   - Open dining sessions should make tables Occupied.
   - Confirmed reservations without a dining session should make tables Reserved.
   - Tables with neither condition should be Available unless under Maintenance.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_SyncTableStatuses
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    UPDATE rt
    SET table_status =
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM Dining_Sessions ds
                WHERE ds.table_id = rt.table_id
                  AND ds.session_status = 'Open'
            )
            THEN 'Occupied'

            WHEN rt.table_status = 'Maintenance'
            THEN 'Maintenance'

            WHEN EXISTS (
                SELECT 1
                FROM Reservations r
                WHERE r.table_id = rt.table_id
                  AND r.reservation_status = 'Confirmed'
                  AND NOT EXISTS (
                      SELECT 1
                      FROM Dining_Sessions ds
                      WHERE ds.reservation_id = r.reservation_id
                  )
            )
            THEN 'Reserved'

            ELSE 'Available'
        END
    FROM Restaurant_Tables rt;

    COMMIT TRANSACTION;
END;
GO

/* ============================================================
   Stored Procedure: Open Dining Session From Reservation
   Purpose:
   - Convert a confirmed reservation into an active dining session.
   - Enforce staff branch ownership.
   - Mark the table as occupied in the same transaction.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_OpenDiningSessionFromReservation
    @reservation_id INT,
    @staff_branch_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @customer_id INT,
        @table_id INT,
        @reservation_status VARCHAR(20),
        @table_status VARCHAR(20),
        @reservation_branch_id INT;

    SELECT
        @customer_id = r.customer_id,
        @table_id = r.table_id,
        @reservation_status = r.reservation_status,
        @table_status = rt.table_status,
        @reservation_branch_id = da.branch_id
    FROM Reservations r
    JOIN Restaurant_Tables rt ON r.table_id = rt.table_id
    JOIN Dining_Areas da ON rt.area_id = da.area_id
    WHERE r.reservation_id = @reservation_id;

    IF @customer_id IS NULL
    BEGIN
        RAISERROR('Reservation not found.', 16, 1);
        RETURN;
    END;

    IF @reservation_branch_id <> @staff_branch_id
    BEGIN
        RAISERROR('This reservation does not belong to the staff member''s branch.', 16, 1);
        RETURN;
    END;

    IF @reservation_status <> 'Confirmed'
    BEGIN
        RAISERROR('Only confirmed reservations can be opened as dining sessions.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM Dining_Sessions
        WHERE reservation_id = @reservation_id
    )
    BEGIN
        RAISERROR('A dining session already exists for this reservation.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM Dining_Sessions
        WHERE table_id = @table_id
          AND session_status = 'Open'
    )
    BEGIN
        RAISERROR('This table already has an open dining session.', 16, 1);
        RETURN;
    END;

    IF @table_status NOT IN ('Reserved', 'Available')
    BEGIN
        RAISERROR('The reservation table is not ready to be occupied.', 16, 1);
        RETURN;
    END;

    BEGIN TRANSACTION;

    INSERT INTO Dining_Sessions (
        customer_id,
        table_id,
        reservation_id,
        session_start,
        session_status
    )
    VALUES (
        @customer_id,
        @table_id,
        @reservation_id,
        GETDATE(),
        'Open'
    );

    UPDATE Restaurant_Tables
    SET table_status = 'Occupied'
    WHERE table_id = @table_id;

    COMMIT TRANSACTION;
END;
GO

/* ============================================================
   Stored Procedure: Open Walk-In Dining Session
   Purpose:
   - Find or create a customer by phone.
   - Open a dining session without a reservation.
   - Enforce staff branch ownership for the selected table.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_OpenWalkInDiningSession
    @staff_branch_id INT,
    @full_name VARCHAR(100),
    @phone VARCHAR(20),
    @email VARCHAR(100) = NULL,
    @table_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @customer_id INT,
        @table_branch_id INT,
        @table_status VARCHAR(20);

    SET @full_name = LTRIM(RTRIM(@full_name));
    SET @phone = LTRIM(RTRIM(@phone));
    SET @email = NULLIF(LTRIM(RTRIM(@email)), '');

    IF @full_name = '' OR @phone = ''
    BEGIN
        RAISERROR('Walk-in customer name and phone are required.', 16, 1);
        RETURN;
    END;

    SELECT
        @table_branch_id = da.branch_id,
        @table_status = rt.table_status
    FROM Restaurant_Tables rt
    JOIN Dining_Areas da ON rt.area_id = da.area_id
    WHERE rt.table_id = @table_id;

    IF @table_branch_id IS NULL
    BEGIN
        RAISERROR('Selected table was not found.', 16, 1);
        RETURN;
    END;

    IF @table_branch_id <> @staff_branch_id
    BEGIN
        RAISERROR('Selected table does not belong to the staff member''s branch.', 16, 1);
        RETURN;
    END;

    IF @table_status <> 'Available'
    BEGIN
        RAISERROR('Walk-in sessions can only use available tables.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM Dining_Sessions
        WHERE table_id = @table_id
          AND session_status = 'Open'
    )
    BEGIN
        RAISERROR('This table already has an open dining session.', 16, 1);
        RETURN;
    END;

    SELECT @customer_id = customer_id
    FROM Customers
    WHERE phone = @phone;

    IF @customer_id IS NULL
    BEGIN
        IF @email IS NOT NULL
           AND EXISTS (SELECT 1 FROM Customers WHERE email = @email)
        BEGIN
            RAISERROR('Another customer already uses this email address.', 16, 1);
            RETURN;
        END;
    END;

    BEGIN TRANSACTION;

    IF @customer_id IS NULL
    BEGIN
        INSERT INTO Customers (full_name, phone, email)
        VALUES (@full_name, @phone, @email);

        SET @customer_id = SCOPE_IDENTITY();
    END;

    INSERT INTO Dining_Sessions (
        customer_id,
        table_id,
        reservation_id,
        session_start,
        session_status
    )
    VALUES (
        @customer_id,
        @table_id,
        NULL,
        GETDATE(),
        'Open'
    );

    UPDATE Restaurant_Tables
    SET table_status = 'Occupied'
    WHERE table_id = @table_id;

    COMMIT TRANSACTION;
END;
GO

/* ============================================================
   Stored Procedure: Create Order With Items
   Purpose:
   - Create one order for an open dining session.
   - Insert multiple related order items in the same transaction.
   - Copy the current branch menu price into agreed_unit_price.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_CreateOrderWithItems
    @session_id INT,
    @staff_id INT,
    @staff_branch_id INT,
    @items_json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @session_branch_id INT,
        @session_status VARCHAR(20),
        @staff_actual_branch_id INT,
        @staff_status VARCHAR(20),
        @order_id INT;

    DECLARE @RawItems TABLE (
        item_id INT NULL,
        quantity INT NULL
    );

    DECLARE @OrderItems TABLE (
        item_id INT NOT NULL PRIMARY KEY,
        quantity INT NOT NULL
    );

    SELECT
        @session_branch_id = da.branch_id,
        @session_status = ds.session_status
    FROM Dining_Sessions ds
    JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
    JOIN Dining_Areas da ON rt.area_id = da.area_id
    WHERE ds.session_id = @session_id;

    IF @session_branch_id IS NULL
    BEGIN
        RAISERROR('Dining session not found.', 16, 1);
        RETURN;
    END;

    IF @session_status <> 'Open'
    BEGIN
        RAISERROR('Orders can only be created for open dining sessions.', 16, 1);
        RETURN;
    END;

    IF @session_branch_id <> @staff_branch_id
    BEGIN
        RAISERROR('This dining session does not belong to the staff member''s branch.', 16, 1);
        RETURN;
    END;

    SELECT
        @staff_actual_branch_id = branch_id,
        @staff_status = staff_status
    FROM Staff
    WHERE staff_id = @staff_id;

    IF @staff_actual_branch_id IS NULL
    BEGIN
        RAISERROR('Staff member not found.', 16, 1);
        RETURN;
    END;

    IF @staff_status <> 'Active'
    BEGIN
        RAISERROR('Inactive staff members cannot create orders.', 16, 1);
        RETURN;
    END;

    IF @staff_actual_branch_id <> @staff_branch_id
    BEGIN
        RAISERROR('Staff member does not belong to the selected branch.', 16, 1);
        RETURN;
    END;

    IF ISJSON(@items_json) <> 1
    BEGIN
        RAISERROR('Order item data is not valid JSON.', 16, 1);
        RETURN;
    END;

    INSERT INTO @RawItems (item_id, quantity)
    SELECT item_id, quantity
    FROM OPENJSON(@items_json)
    WITH (
        item_id INT '$.item_id',
        quantity INT '$.quantity'
    );

    IF NOT EXISTS (SELECT 1 FROM @RawItems)
    BEGIN
        RAISERROR('At least one menu item is required.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM @RawItems
        WHERE item_id IS NULL
           OR quantity IS NULL
           OR quantity <= 0
    )
    BEGIN
        RAISERROR('Every order item must have a valid menu item and positive quantity.', 16, 1);
        RETURN;
    END;

    INSERT INTO @OrderItems (item_id, quantity)
    SELECT item_id, SUM(quantity)
    FROM @RawItems
    GROUP BY item_id;

    IF EXISTS (
        SELECT 1
        FROM @OrderItems oi
        LEFT JOIN Branch_Menu_Items bmi
            ON oi.item_id = bmi.item_id
           AND bmi.branch_id = @staff_branch_id
           AND bmi.availability_status = 'Available'
        WHERE bmi.item_id IS NULL
    )
    BEGIN
        RAISERROR('One or more selected menu items are not available at this branch.', 16, 1);
        RETURN;
    END;

    BEGIN TRANSACTION;

    INSERT INTO [Orders] (
        session_id,
        staff_id,
        order_datetime,
        order_status
    )
    VALUES (
        @session_id,
        @staff_id,
        GETDATE(),
        'Placed'
    );

    SET @order_id = SCOPE_IDENTITY();

    INSERT INTO Order_Items (
        order_id,
        item_id,
        quantity,
        agreed_unit_price
    )
    SELECT
        @order_id,
        oi.item_id,
        oi.quantity,
        bmi.price
    FROM @OrderItems oi
    JOIN Branch_Menu_Items bmi
        ON oi.item_id = bmi.item_id
       AND bmi.branch_id = @staff_branch_id
       AND bmi.availability_status = 'Available';

    COMMIT TRANSACTION;
END;
GO

/* ============================================================
   Stored Procedure: Update Order Status
   Purpose:
   - Enforce staff branch ownership for order status updates.
   - Control a simple service workflow: Placed -> Preparing -> Served.
   - Allow cancellation before an order is served or paid.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_UpdateOrderStatus
    @order_id INT,
    @staff_branch_id INT,
    @new_status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @current_status VARCHAR(20),
        @order_branch_id INT,
        @payment_id INT;

    SELECT
        @current_status = o.order_status,
        @order_branch_id = da.branch_id,
        @payment_id = p.payment_id
    FROM [Orders] o
    JOIN Dining_Sessions ds ON o.session_id = ds.session_id
    JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
    JOIN Dining_Areas da ON rt.area_id = da.area_id
    LEFT JOIN Payments p ON o.order_id = p.order_id
    WHERE o.order_id = @order_id;

    IF @current_status IS NULL
    BEGIN
        RAISERROR('Order not found.', 16, 1);
        RETURN;
    END;

    IF @order_branch_id <> @staff_branch_id
    BEGIN
        RAISERROR('This order does not belong to the staff member''s branch.', 16, 1);
        RETURN;
    END;

    IF @new_status NOT IN ('Preparing', 'Served', 'Cancelled')
    BEGIN
        RAISERROR('Invalid order status update.', 16, 1);
        RETURN;
    END;

    IF @current_status = 'Cancelled'
    BEGIN
        RAISERROR('Cancelled orders cannot be changed.', 16, 1);
        RETURN;
    END;

    IF @current_status = 'Served' AND @new_status <> 'Cancelled'
    BEGIN
        RAISERROR('Served orders are already final for preparation workflow.', 16, 1);
        RETURN;
    END;

    IF @new_status = 'Preparing' AND @current_status <> 'Placed'
    BEGIN
        RAISERROR('Only placed orders can be marked as preparing.', 16, 1);
        RETURN;
    END;

    IF @new_status = 'Served' AND @current_status NOT IN ('Placed', 'Preparing')
    BEGIN
        RAISERROR('Only placed or preparing orders can be marked as served.', 16, 1);
        RETURN;
    END;

    IF @new_status = 'Cancelled'
    BEGIN
        IF @current_status = 'Served'
        BEGIN
            RAISERROR('Served orders should not be cancelled from this workflow.', 16, 1);
            RETURN;
        END;

        IF @payment_id IS NOT NULL
        BEGIN
            RAISERROR('Paid orders cannot be cancelled.', 16, 1);
            RETURN;
        END;
    END;

    UPDATE [Orders]
    SET order_status = @new_status
    WHERE order_id = @order_id;
END;
GO

/* ============================================================
   Stored Procedure: Record Order Payment
   Purpose:
   - Calculate the amount from Order_Items.
   - Prevent duplicate payments for the same order.
   - Insert one payment row for the order.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_RecordOrderPayment
    @order_id INT,
    @staff_branch_id INT,
    @payment_method VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @order_branch_id INT,
        @order_status VARCHAR(20),
        @amount_paid DECIMAL(10,2);

    SELECT
        @order_branch_id = da.branch_id,
        @order_status = o.order_status
    FROM [Orders] o
    JOIN Dining_Sessions ds ON o.session_id = ds.session_id
    JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
    JOIN Dining_Areas da ON rt.area_id = da.area_id
    WHERE o.order_id = @order_id;

    IF @order_branch_id IS NULL
    BEGIN
        RAISERROR('Order not found.', 16, 1);
        RETURN;
    END;

    IF @order_branch_id <> @staff_branch_id
    BEGIN
        RAISERROR('This order does not belong to the staff member''s branch.', 16, 1);
        RETURN;
    END;

    IF @order_status = 'Cancelled'
    BEGIN
        RAISERROR('Cancelled orders cannot be paid.', 16, 1);
        RETURN;
    END;

    IF @payment_method NOT IN ('Cash', 'Card', 'MobilePayment')
    BEGIN
        RAISERROR('Invalid payment method.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM Payments
        WHERE order_id = @order_id
    )
    BEGIN
        RAISERROR('This order already has a payment record.', 16, 1);
        RETURN;
    END;

    SELECT
        @amount_paid = COALESCE(SUM(quantity * agreed_unit_price), 0)
    FROM Order_Items
    WHERE order_id = @order_id;

    IF @amount_paid <= 0
    BEGIN
        RAISERROR('Cannot record payment for an order without billable items.', 16, 1);
        RETURN;
    END;

    INSERT INTO Payments (
        order_id,
        payment_method,
        amount_paid,
        payment_datetime,
        payment_status
    )
    VALUES (
        @order_id,
        @payment_method,
        @amount_paid,
        GETDATE(),
        'Paid'
    );
END;
GO

/* ============================================================
   Stored Procedure: Close Dining Session
   Purpose:
   - Close an open dining session after all orders are paid or cancelled.
   - Release the restaurant table back to Available.
   - Mark linked reservations as Completed.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_CloseDiningSession
    @session_id INT,
    @staff_branch_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @session_status VARCHAR(20),
        @session_branch_id INT,
        @table_id INT,
        @reservation_id INT;

    SELECT
        @session_status = ds.session_status,
        @session_branch_id = da.branch_id,
        @table_id = ds.table_id,
        @reservation_id = ds.reservation_id
    FROM Dining_Sessions ds
    JOIN Restaurant_Tables rt ON ds.table_id = rt.table_id
    JOIN Dining_Areas da ON rt.area_id = da.area_id
    WHERE ds.session_id = @session_id;

    IF @session_status IS NULL
    BEGIN
        RAISERROR('Dining session not found.', 16, 1);
        RETURN;
    END;

    IF @session_branch_id <> @staff_branch_id
    BEGIN
        RAISERROR('This dining session does not belong to the staff member''s branch.', 16, 1);
        RETURN;
    END;

    IF @session_status <> 'Open'
    BEGIN
        RAISERROR('Only open dining sessions can be closed.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM [Orders] o
        WHERE o.session_id = @session_id
          AND o.order_status <> 'Cancelled'
          AND NOT EXISTS (
              SELECT 1
              FROM Payments p
              WHERE p.order_id = o.order_id
                AND p.payment_status = 'Paid'
          )
    )
    BEGIN
        RAISERROR('This session still has unpaid active orders.', 16, 1);
        RETURN;
    END;

    BEGIN TRANSACTION;

    UPDATE Dining_Sessions
    SET
        session_status = 'Closed',
        session_end = GETDATE()
    WHERE session_id = @session_id;

    UPDATE Restaurant_Tables
    SET table_status = 'Available'
    WHERE table_id = @table_id;

    IF @reservation_id IS NOT NULL
    BEGIN
        UPDATE Reservations
        SET reservation_status = 'Completed'
        WHERE reservation_id = @reservation_id
          AND reservation_status = 'Confirmed';
    END;

    COMMIT TRANSACTION;
END;
GO

/* ============================================================
   Stored Procedure: Admin Add Menu Item
   Purpose:
   - Create a menu item once in Menu_Items.
   - Assign it to one branch with price and availability.
   - Keep both inserts in one transaction.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_AdminAddMenuItem
    @category_id INT,
    @item_name VARCHAR(100),
    @calories INT = NULL,
    @description VARCHAR(255) = NULL,
    @branch_id INT,
    @price DECIMAL(10,2),
    @availability_status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @item_id INT;

    SET @item_name = LTRIM(RTRIM(@item_name));
    SET @description = NULLIF(LTRIM(RTRIM(@description)), '');

    IF @item_name = ''
    BEGIN
        RAISERROR('Menu item name is required.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM Menu_Categories
        WHERE category_id = @category_id
    )
    BEGIN
        RAISERROR('Selected menu category does not exist.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM Branches
        WHERE branch_id = @branch_id
    )
    BEGIN
        RAISERROR('Selected branch does not exist.', 16, 1);
        RETURN;
    END;

    IF @calories IS NOT NULL AND @calories < 0
    BEGIN
        RAISERROR('Calories cannot be negative.', 16, 1);
        RETURN;
    END;

    IF @price < 0
    BEGIN
        RAISERROR('Price cannot be negative.', 16, 1);
        RETURN;
    END;

    IF @availability_status NOT IN ('Available', 'Unavailable')
    BEGIN
        RAISERROR('Invalid menu availability status.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM Menu_Items mi
        JOIN Branch_Menu_Items bmi ON mi.item_id = bmi.item_id
        WHERE mi.category_id = @category_id
          AND mi.item_name = @item_name
          AND bmi.branch_id = @branch_id
    )
    BEGIN
        RAISERROR('This branch already has a menu item with the same name and category.', 16, 1);
        RETURN;
    END;

    BEGIN TRANSACTION;

    INSERT INTO Menu_Items (
        category_id,
        item_name,
        calories,
        description
    )
    VALUES (
        @category_id,
        @item_name,
        @calories,
        @description
    );

    SET @item_id = SCOPE_IDENTITY();

    INSERT INTO Branch_Menu_Items (
        branch_id,
        item_id,
        price,
        availability_status
    )
    VALUES (
        @branch_id,
        @item_id,
        @price,
        @availability_status
    );

    COMMIT TRANSACTION;
END;
GO


/* ============================================================
   Stored Procedure: Admin Update Branch Menu Item
   Purpose:
   - Update branch-specific menu price and availability.
   - Keep historical Order_Items unchanged because they store agreed price.
   - Use Unavailable as the safe remove option for menu history.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_AdminUpdateBranchMenuItem
    @branch_id INT,
    @item_id INT,
    @price DECIMAL(10,2),
    @availability_status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM Branch_Menu_Items
        WHERE branch_id = @branch_id
          AND item_id = @item_id
    )
    BEGIN
        RAISERROR('Branch menu item was not found.', 16, 1);
        RETURN;
    END;

    IF @price < 0
    BEGIN
        RAISERROR('Price cannot be negative.', 16, 1);
        RETURN;
    END;

    IF @availability_status NOT IN ('Available', 'Unavailable')
    BEGIN
        RAISERROR('Invalid menu availability status.', 16, 1);
        RETURN;
    END;

    UPDATE Branch_Menu_Items
    SET
        price = @price,
        availability_status = @availability_status
    WHERE branch_id = @branch_id
      AND item_id = @item_id;
END;
GO

/* ============================================================
   Stored Procedure: Admin Add Staff
   Purpose:
   - Add a staff member using existing branch and staff role records.
   - Validate phone uniqueness and allowed staff statuses.
   - Keep staff assignment clean for staff login and branch-limited pages.
   ============================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_AdminAddStaff
    @branch_id INT,
    @role_id INT,
    @full_name VARCHAR(100),
    @phone VARCHAR(20),
    @hire_date DATE,
    @salary DECIMAL(10,2),
    @staff_status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @full_name = LTRIM(RTRIM(@full_name));
    SET @phone = LTRIM(RTRIM(@phone));

    IF @full_name = '' OR @phone = ''
    BEGIN
        RAISERROR('Staff name and phone are required.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM Branches
        WHERE branch_id = @branch_id
    )
    BEGIN
        RAISERROR('Selected branch does not exist.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM Staff_Roles
        WHERE role_id = @role_id
    )
    BEGIN
        RAISERROR('Selected staff role does not exist.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM Staff
        WHERE phone = @phone
    )
    BEGIN
        RAISERROR('A staff member with this phone already exists.', 16, 1);
        RETURN;
    END;

    IF @salary < 0
    BEGIN
        RAISERROR('Salary cannot be negative.', 16, 1);
        RETURN;
    END;

    IF @staff_status NOT IN ('Active', 'Inactive', 'OnLeave')
    BEGIN
        RAISERROR('Invalid staff status.', 16, 1);
        RETURN;
    END;

    INSERT INTO Staff (
        branch_id,
        role_id,
        full_name,
        phone,
        hire_date,
        salary,
        staff_status
    )
    VALUES (
        @branch_id,
        @role_id,
        @full_name,
        @phone,
        @hire_date,
        @salary,
        @staff_status
    );
END;
GO



EXEC dbo.sp_SyncTableStatuses;


UPDATE r
SET r.reservation_status = 'Completed'
FROM Reservations r
JOIN Dining_Sessions ds
    ON r.reservation_id = ds.reservation_id
WHERE ds.session_status = 'Closed'
  AND r.reservation_status = 'Confirmed';
