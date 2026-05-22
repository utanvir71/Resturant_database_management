USE rdb_3;
GO

/* =========================
   DROP TABLES IF THEY EXIST
   ========================= */
DROP TABLE IF EXISTS Feedback;
DROP TABLE IF EXISTS Order_Promotions;
DROP TABLE IF EXISTS Payments;
DROP TABLE IF EXISTS Order_Items;
DROP TABLE IF EXISTS [Orders];
DROP TABLE IF EXISTS Dining_Sessions;
DROP TABLE IF EXISTS Reservations;
DROP TABLE IF EXISTS Branch_Menu_Items;
DROP TABLE IF EXISTS Menu_Items;
DROP TABLE IF EXISTS Shifts;
DROP TABLE IF EXISTS Staff;
DROP TABLE IF EXISTS Restaurant_Tables;
DROP TABLE IF EXISTS Dining_Areas;
DROP TABLE IF EXISTS Promotions;
DROP TABLE IF EXISTS Menu_Categories;
DROP TABLE IF EXISTS Staff_Roles;
DROP TABLE IF EXISTS Customers;
DROP TABLE IF EXISTS Branches;
GO

/* =========================
   1. Branches
   ========================= */
CREATE TABLE Branches (
    branch_id INT IDENTITY(1,1) PRIMARY KEY,
    branch_name VARCHAR(100) NOT NULL,
    location VARCHAR(200) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    opening_time TIME NOT NULL,
    closing_time TIME NOT NULL,
    CONSTRAINT CHK_Branches_Hours CHECK (opening_time < closing_time)
);
GO

/* =========================
   2. Customers
   ========================= */
CREATE TABLE Customers (
    customer_id INT IDENTITY(1,1) PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    loyalty_points INT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT GETDATE(),
    CONSTRAINT CHK_Customers_Loyalty CHECK (loyalty_points >= 0)
);
GO

/* =========================
   3. Staff_Roles
   ========================= */
CREATE TABLE Staff_Roles (
    role_id INT IDENTITY(1,1) PRIMARY KEY,
    role_name VARCHAR(50) NOT NULL UNIQUE
);
GO

/* =========================
   4. Menu_Categories
   ========================= */
CREATE TABLE Menu_Categories (
    category_id INT IDENTITY(1,1) PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL UNIQUE
);
GO

/* =========================
   5. Promotions
   ========================= */
CREATE TABLE Promotions (
    promo_id INT IDENTITY(1,1) PRIMARY KEY,
    promo_name VARCHAR(100) NOT NULL,
    discount_type VARCHAR(20) NOT NULL,
    discount_value DECIMAL(10,2) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    min_order_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT CHK_Promotions_Discount CHECK (discount_value >= 0),
    CONSTRAINT CHK_Promotions_MinOrder CHECK (min_order_amount >= 0),
    CONSTRAINT CHK_Promotions_Dates CHECK (start_date <= end_date),
    CONSTRAINT CHK_Promotions_Type CHECK (discount_type IN ('Percentage', 'Flat'))
);
GO

/* =========================
   6. Dining_Areas
   ========================= */
CREATE TABLE Dining_Areas (
    area_id INT IDENTITY(1,1) PRIMARY KEY,
    branch_id INT NOT NULL,
    area_name VARCHAR(100) NOT NULL,
    area_type VARCHAR(30) NOT NULL,
    CONSTRAINT FK_Dining_Areas_Branches
        FOREIGN KEY (branch_id) REFERENCES Branches(branch_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT UQ_Dining_Areas UNIQUE (branch_id, area_name),
    CONSTRAINT CHK_Dining_Areas_Type CHECK (area_type IN ('Indoor', 'Outdoor', 'VIP', 'Private'))
);
GO

/* =========================
   7. Restaurant_Tables
   ========================= */
CREATE TABLE Restaurant_Tables (
    table_id INT IDENTITY(1,1) PRIMARY KEY,
    area_id INT NOT NULL,
    table_number VARCHAR(10) NOT NULL,
    capacity INT NOT NULL,
    table_status VARCHAR(20) NOT NULL DEFAULT 'Available',
    CONSTRAINT FK_Restaurant_Tables_Dining_Areas
        FOREIGN KEY (area_id) REFERENCES Dining_Areas(area_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT UQ_Restaurant_Tables UNIQUE (area_id, table_number),
    CONSTRAINT CHK_Restaurant_Tables_Capacity CHECK (capacity > 0),
    CONSTRAINT CHK_Restaurant_Tables_Status CHECK (table_status IN ('Available', 'Reserved', 'Occupied', 'Maintenance'))
);
GO

/* =========================
   8. Staff
   ========================= */
CREATE TABLE Staff (
    staff_id INT IDENTITY(1,1) PRIMARY KEY,
    branch_id INT NOT NULL,
    role_id INT NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    hire_date DATE NOT NULL,
    salary DECIMAL(10,2) NOT NULL,
    staff_status VARCHAR(20) NOT NULL DEFAULT 'Active',
    CONSTRAINT FK_Staff_Branches
        FOREIGN KEY (branch_id) REFERENCES Branches(branch_id)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT FK_Staff_Staff_Roles
        FOREIGN KEY (role_id) REFERENCES Staff_Roles(role_id)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Staff_Salary CHECK (salary >= 0),
    CONSTRAINT CHK_Staff_Status CHECK (staff_status IN ('Active', 'Inactive', 'OnLeave'))
);
GO

/* =========================
   9. Shifts
   ========================= */
CREATE TABLE Shifts (
    shift_id INT IDENTITY(1,1) PRIMARY KEY,
    staff_id INT NOT NULL,
    shift_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    shift_status VARCHAR(20) NOT NULL DEFAULT 'Scheduled',
    CONSTRAINT FK_Shifts_Staff
        FOREIGN KEY (staff_id) REFERENCES Staff(staff_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Shifts_Time CHECK (start_time < end_time),
    CONSTRAINT CHK_Shifts_Status CHECK (shift_status IN ('Scheduled', 'Completed', 'Cancelled'))
);
GO

/* =========================
   10. Menu_Items
   ========================= */
CREATE TABLE Menu_Items (
    item_id INT IDENTITY(1,1) PRIMARY KEY,
    category_id INT NOT NULL,
    item_name VARCHAR(100) NOT NULL,
    calories INT NULL,
    description VARCHAR(255) NULL,
    CONSTRAINT FK_Menu_Items_Menu_Categories
        FOREIGN KEY (category_id) REFERENCES Menu_Categories(category_id)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Menu_Items_Calories CHECK (calories IS NULL OR calories >= 0)
);
GO

/* =========================
   11. Branch_Menu_Items
   ========================= */
CREATE TABLE Branch_Menu_Items (
    branch_id INT NOT NULL,
    item_id INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    availability_status VARCHAR(20) NOT NULL DEFAULT 'Available',
    PRIMARY KEY (branch_id, item_id),
    CONSTRAINT FK_Branch_Menu_Items_Branches
        FOREIGN KEY (branch_id) REFERENCES Branches(branch_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_Branch_Menu_Items_Menu_Items
        FOREIGN KEY (item_id) REFERENCES Menu_Items(item_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Branch_Menu_Items_Price CHECK (price >= 0),
    CONSTRAINT CHK_Branch_Menu_Items_Status CHECK (availability_status IN ('Available', 'Unavailable'))
);
GO

/* =========================
   12. Reservations
   ========================= */
CREATE TABLE Reservations (
    reservation_id INT IDENTITY(1,1) PRIMARY KEY,
    customer_id INT NOT NULL,
    table_id INT NOT NULL,
    reservation_datetime DATETIME NOT NULL,
    party_size INT NOT NULL,
    reservation_status VARCHAR(20) NOT NULL DEFAULT 'Pending',
    special_request VARCHAR(255) NULL,
    CONSTRAINT FK_Reservations_Customers
        FOREIGN KEY (customer_id) REFERENCES Customers(customer_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_Reservations_Restaurant_Tables
        FOREIGN KEY (table_id) REFERENCES Restaurant_Tables(table_id)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Reservations_PartySize CHECK (party_size > 0),
    CONSTRAINT CHK_Reservations_Status CHECK (
        reservation_status IN ('Pending', 'Confirmed', 'Completed', 'Cancelled', 'NoShow')
    )
);
GO

/* =========================
   13. Dining_Sessions
   ========================= */
CREATE TABLE Dining_Sessions (
    session_id INT IDENTITY(1,1) PRIMARY KEY,
    customer_id INT NOT NULL,
    table_id INT NOT NULL,
    reservation_id INT NULL UNIQUE,
    session_start DATETIME NOT NULL,
    session_end DATETIME NULL,
    session_status VARCHAR(20) NOT NULL DEFAULT 'Open',
    CONSTRAINT FK_Dining_Sessions_Customers
        FOREIGN KEY (customer_id) REFERENCES Customers(customer_id)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT FK_Dining_Sessions_Restaurant_Tables
        FOREIGN KEY (table_id) REFERENCES Restaurant_Tables(table_id)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT FK_Dining_Sessions_Reservations
        FOREIGN KEY (reservation_id) REFERENCES Reservations(reservation_id)
        ON DELETE NO ACTION
        ON UPDATE NO ACTION,
    CONSTRAINT CHK_Dining_Sessions_Time CHECK (
        session_end IS NULL OR session_start <= session_end
    ),
    CONSTRAINT CHK_Dining_Sessions_Status CHECK (
        session_status IN ('Open', 'Closed', 'Cancelled')
    )
);
GO

CREATE TABLE [Orders] (
    order_id INT IDENTITY(1,1) PRIMARY KEY,
    session_id INT NOT NULL,
    staff_id INT NOT NULL,
    order_datetime DATETIME NOT NULL DEFAULT GETDATE(),
    order_status VARCHAR(20) NOT NULL DEFAULT 'Placed',
    CONSTRAINT FK_Orders_Dining_Sessions
        FOREIGN KEY (session_id) REFERENCES Dining_Sessions(session_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_Orders_Staff
        FOREIGN KEY (staff_id) REFERENCES Staff(staff_id)
        ON DELETE NO ACTION
        ON UPDATE NO ACTION,
    CONSTRAINT CHK_Orders_Status CHECK (
        order_status IN ('Placed', 'Preparing', 'Served', 'Cancelled')
    )
);
GO

CREATE TABLE Order_Items (
    order_item_id INT IDENTITY(1,1) PRIMARY KEY,
    order_id INT NOT NULL,
    item_id INT NOT NULL,
    quantity INT NOT NULL,
    agreed_unit_price DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_Order_Items_Orders
        FOREIGN KEY (order_id) REFERENCES [Orders](order_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_Order_Items_Menu_Items
        FOREIGN KEY (item_id) REFERENCES Menu_Items(item_id)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Order_Items_Quantity CHECK (quantity > 0),
    CONSTRAINT CHK_Order_Items_Price CHECK (agreed_unit_price >= 0)
);
GO

CREATE TABLE Payments (
    payment_id INT IDENTITY(1,1) PRIMARY KEY,
    order_id INT NOT NULL,
    payment_method VARCHAR(20) NOT NULL,
    amount_paid DECIMAL(10,2) NOT NULL,
    payment_datetime DATETIME NOT NULL DEFAULT GETDATE(),
    payment_status VARCHAR(20) NOT NULL DEFAULT 'Paid',
    CONSTRAINT FK_Payments_Orders
        FOREIGN KEY (order_id) REFERENCES [Orders](order_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Payments_Amount CHECK (amount_paid >= 0),
    CONSTRAINT CHK_Payments_Method CHECK (
        payment_method IN ('Cash', 'Card', 'MobilePayment')
    ),
    CONSTRAINT CHK_Payments_Status CHECK (
        payment_status IN ('Pending', 'Paid', 'Failed', 'Refunded')
    )
);
GO

CREATE TABLE Order_Promotions (
    order_id INT NOT NULL,
    promo_id INT NOT NULL,
    discount_applied DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, promo_id),
    CONSTRAINT FK_Order_Promotions_Orders
        FOREIGN KEY (order_id) REFERENCES [Orders](order_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_Order_Promotions_Promotions
        FOREIGN KEY (promo_id) REFERENCES Promotions(promo_id)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Order_Promotions_Discount CHECK (discount_applied >= 0)
);
GO

CREATE TABLE Feedback (
    feedback_id INT IDENTITY(1,1) PRIMARY KEY,
    session_id INT NOT NULL UNIQUE,
    rating INT NOT NULL,
    comments VARCHAR(500) NULL,
    feedback_date DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    CONSTRAINT FK_Feedback_Dining_Sessions
        FOREIGN KEY (session_id) REFERENCES Dining_Sessions(session_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT CHK_Feedback_Rating CHECK (rating BETWEEN 1 AND 5)
);
GO


SELECT TABLE_NAME 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_TYPE = 'BASE TABLE';