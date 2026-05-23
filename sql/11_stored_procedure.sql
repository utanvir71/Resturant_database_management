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
