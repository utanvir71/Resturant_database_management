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
