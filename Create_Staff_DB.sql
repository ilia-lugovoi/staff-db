SET NOCOUNT ON;
GO

-- #1 Создаем основу БД

CREATE TABLE Departments(
  ID int IDENTITY(1,1) NOT NULL,
  Name nvarchar(100) NOT NULL,
  CONSTRAINT PK_Departments PRIMARY KEY(ID)
);
GO

CREATE TABLE Positions(
  ID int NOT NULL, -- вводим вручную, в зависимости от отдела
  Name nvarchar(100) NOT NULL,
  DepartmentID int NOT NULL,
  CONSTRAINT PK_Positions PRIMARY KEY(ID),
  CONSTRAINT FK_Positions_Departments FOREIGN KEY(DepartmentID) REFERENCES Departments(ID)
);
GO

CREATE TABLE Employees(
	ID int IDENTITY(1,1) NOT NULL,
	FirstName nvarchar(50) NOT NULL,
	LastName nvarchar(50) NOT NULL,
    MiddleName nvarchar(50),
	Birthday date,
	Email nvarchar(100) UNIQUE,
	PositionID int, -- содержит номер отдела
	ManagerID int,
    HireDate date NOT NULL,
    Salary decimal(18,2),
    BonusPercent decimal(18,2),
	CONSTRAINT PK_Employees PRIMARY KEY (ID)
);
GO

ALTER TABLE Employees ADD CONSTRAINT FK_Employees_PositionID
FOREIGN KEY(PositionID) REFERENCES Positions(ID);
GO

ALTER TABLE Employees ADD CONSTRAINT FK_Employees_ManagerID
FOREIGN KEY(ManagerID) REFERENCES Employees(ID);
GO

CREATE INDEX IDX_Employees_FullName ON Employees(LastName, FirstName);
GO


-- #2 Нанимаем первых сотрудников

INSERT Departments(Name) VALUES
(N'Management'), -- 1
(N'Software development'), -- 2
(N'IT security'), -- 3
(N'Accounting'); -- 4
GO

INSERT Positions(ID, Name, DepartmentID) VALUES
(101, N'Chief executive officer', 1),
(102, N'Chief administrative officer', 1),
(201, N'Chief software engineer', 2),
(301, N'Chief safety officer', 3),
(401, N'The chief accountant', 4),
(202, N'Senior Developer', 2);
GO

INSERT Employees (FirstName, LastName, Email, PositionID, HireDate, Salary, BonusPercent) VALUES
('Илья', 'Луговой', 'lugovoi@staff.com', 101, DATEFROMPARTS(2022,3,16), 4000, 25),
('Илья', 'Маслов', 'maslov@staff.com', 102, DATEFROMPARTS(2022,3,16), 4000, 25),
('Сидор', 'Сидоров', 'sidor@staff.com', 201, DATEFROMPARTS(2022,3,16), 4000, 25),
('Владислав', 'Резник', 'reznik@staff.com', 301, DATEFROMPARTS(2022,3,16), 4000, 25),
('Петр', 'Петров', 'petrov@staff.com', 202, DATEFROMPARTS(2022,3,17), 3000, 25),
('Андрей', 'Андреев', 'andrey@staff.com', 401, DATEFROMPARTS(2022,4,16), 3000, 25);
GO

-- назначаем ManagerID
UPDATE e
SET ManagerID = CASE
    WHEN ID = 2 THEN 1
    WHEN ID = 3 THEN 1
    WHEN ID = 4 THEN 1
    WHEN ID = 5 THEN 1
    WHEN ID = 6 THEN 3
    ELSE NULL
END
FROM Employees e;
GO


-- #3 Создаем типы бонусов и историю выплат

CREATE TABLE BonusTypes (
    ID int IDENTITY(1,1),
    Name nvarchar(50) NOT NULL,
    CONSTRAINT PK_BonusTypes PRIMARY KEY(ID)
);
GO

INSERT INTO BonusTypes (Name) VALUES (N'Ежемесячная премия'), (N'Квартальный'), (N'Годовой'), (N'За особые успехи');
GO

CREATE TABLE Payroll (
    ID int IDENTITY(1,1),
    EmployeeID int NOT NULL,
    Type nvarchar(20) NOT NULL, -- 'Salary' или 'Bonus'
    Amount decimal(18,2) NOT NULL,
    PaymentDate date NOT NULL,
    BonusTypeID int NULL, -- Только если тип 'Bonus'
    CONSTRAINT PK_Payroll PRIMARY KEY (ID),
    CONSTRAINT FK_Payroll_Employees FOREIGN KEY (EmployeeID) REFERENCES Employees(ID),
    CONSTRAINT FK_Payroll_BonusTypes FOREIGN KEY (BonusTypeID) REFERENCES BonusTypes(ID),
    CONSTRAINT CHK_Payroll_Amount CHECK (Amount > 0)
);
GO


-- #4 Создаем историю изменений ЗП

CREATE TABLE SalaryHistory(
    ID int IDENTITY(1,1) NOT NULL,
    EmployeeID int NOT NULL,
    SalaryAmount decimal(18, 2) NOT NULL,
    BonusPercent decimal(5, 2),
    DateFrom date NOT NULL,
    DateTo date,
    CONSTRAINT PK_SalaryHistory PRIMARY KEY(ID),
    CONSTRAINT FK_SalaryHistory_Employees FOREIGN KEY(EmployeeID) REFERENCES Employees(ID),
    CONSTRAINT UQ_Employee_DateFrom UNIQUE (EmployeeID, DateFrom)
)
GO

INSERT INTO SalaryHistory (EmployeeID, SalaryAmount, BonusPercent, DateFrom, DateTo)
SELECT ID, Salary, BonusPercent, HireDate, NULL
FROM Employees;
GO

CREATE TRIGGER trg_Employees_UpdateSalary
ON Employees
AFTER UPDATE
AS
BEGIN
    -- Срабатывает, если изменилась ЗП ИЛИ Бонус
    IF NOT (UPDATE(Salary) OR UPDATE(BonusPercent)) RETURN;

    -- 1. Закрываем старую запись
    UPDATE sh
    SET sh.DateTo = DATEADD(day, -1, CAST(GETDATE() AS DATE))
    FROM SalaryHistory sh
    INNER JOIN deleted d ON sh.EmployeeID = d.ID
    WHERE sh.DateTo IS NULL;

    -- 2. Открываем новую запись (с актуальными ЗП и Бонусом)
    INSERT INTO SalaryHistory (EmployeeID, SalaryAmount, BonusPercent, DateFrom, DateTo)
    SELECT i.ID, i.Salary, i.BonusPercent, CAST(GETDATE() AS DATE), NULL
    FROM inserted i;
END;
GO

-- !!! из-за отсутствия необходмых процедур, менять ЗП сотрудника можно только раз в день и вчерашним числом !!!

SELECT * FROM SalaryHistory;
GO


-- #5 Расширяем компанию

INSERT INTO Departments (Name) VALUES (N'HR'), (N'Marketing'), (N'Law');
GO

INSERT INTO Positions (ID, Name, DepartmentID) VALUES 
(501, N'HR Manager', 5), (502, N'Recruiter', 5),
(601, N'Marketing Head', 6), (602, N'SMM Specialist', 6),
(701, N'Legal Counsel', 7), (203, N'Middle Developer', 2);
GO

-- Найм с 2022 по 2026

DECLARE @Jobs TABLE (PosID INT, Qnt INT, Sal DECIMAL(18,2));
INSERT INTO @Jobs VALUES 
(202, 20, 4000), -- 20 Senior Dev
(203, 20, 3000), -- 20 Middle Dev
(501, 1, 4500),  -- 1 HR Manager
(502, 2, 4000),  -- 2 Recruiter
(601, 1, 5000),  -- 1 Marketing Head
(602, 2, 3500),  -- 2 SMM
(701, 2, 5000);  -- 2 Legal Counsel

DECLARE @pID INT, @q INT, @s DECIMAL(18,2), @i INT;

DECLARE job_cursor CURSOR FOR SELECT PosID, Qnt, Sal FROM @Jobs;
OPEN job_cursor;
FETCH NEXT FROM job_cursor INTO @pID, @q, @s;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @i = 1;
    WHILE @i <= @q
    BEGIN
        INSERT INTO Employees (FirstName, LastName, Email, PositionID, Salary, BonusPercent, HireDate)
        VALUES (
            N'Имя_' + CAST(@pID AS nvarchar) + N'_' + CAST(@i AS nvarchar), 
            N'Фамилия_' + CAST(@i AS nvarchar),
            'staff_' + CAST(@pID AS nvarchar) + '_' + CAST(@i AS nvarchar) + '@company.com',
            @pID, 
            @s, 
            20, -- Бонус по умолчанию 20%
            DATEADD(day, -CAST(RAND()*1000 AS INT), '20260325') -- Даты найма в районе 2023-2026 годов
        );
        SET @i = @i + 1;
    END
    FETCH NEXT FROM job_cursor INTO @pID, @q, @s;
END
CLOSE job_cursor;
DEALLOCATE job_cursor;
GO

-- Назначаем ManagerID
UPDATE e
SET ManagerID = CASE
    WHEN PositionID = 202 OR PositionID = 203 THEN 3
    WHEN PositionID = 501 THEN 1
    WHEN PositionID = 502 THEN (SELECT ID FROM Employees WHERE PositionID = 501)
    WHEN PositionID = 601 THEN 1
    WHEN PositionID = 602 THEN (SELECT ID FROM Employees WHERE PositionID = 601)
    WHEN PositionID = 701 THEN 2
    ELSE ManagerID
END
FROM Employees e;
GO

-- Корректируем HireDate под бизнес-логику
UPDATE e
SET HireDate = CASE
    WHEN PositionID = 501 THEN DATEFROMPARTS(2023,2,14)
    WHEN PositionID = 601 THEN DATEFROMPARTS(2023,4,26)
    WHEN PositionID = 701 AND FirstName = 'Имя_701_1' THEN DATEFROMPARTS(2022,8,28)
    WHEN PositionID = 701 AND FirstName = 'Имя_701_2' THEN DATEFROMPARTS(2023,5,18)
    ELSE HireDate
END
FROM Employees e;
GO


-- #6 Добавляем процесс увольнения сотрудника (Soft Delete) через отдельную таблицу DismissedEmployees и проведем увольнения

ALTER TABLE Employees ADD DismissDate date NULL;
GO

-- таблица справочник причин увольнения
CREATE TABLE DismissalReasons (
    ID int IDENTITY(1,1) PRIMARY KEY,
    ReasonName nvarchar(100) NOT NULL UNIQUE -- Название причины должно быть уникальным
);
GO

INSERT INTO DismissalReasons (ReasonName) VALUES
(N'По собственному желанию (с передачей дел)'),
(N'По собственному желанию (без передачи дел)'),
(N'Сокращение штата'),
(N'Уволен за некомпетентность'),
(N'Уволен за прогулы'),
(N'Уволен за прогулы и некомпетентность');
GO

CREATE TABLE DismissedEmployees (
    ID int IDENTITY(1,1) PRIMARY KEY, -- Автоматический ID для каждой записи в логе
    EmployeeID int NOT NULL, -- ID сотрудника, которого уволили
    DismissDate date NOT NULL, -- Дата фактического увольнения
    OperationDate datetime NOT NULL DEFAULT GETDATE(), -- Дата внесения записи в лог
    DismissalReasonID int NOT NULL,
    CONSTRAINT FK_DismissedEmployees_DismissalReasons FOREIGN KEY (DismissalReasonID) REFERENCES DismissalReasons(ID),
    CONSTRAINT FK_DismissedEmployees_Employees FOREIGN KEY (EmployeeID) REFERENCES Employees(ID)
);
GO

CREATE TRIGGER trg_DismissedEmployees_AfterInsert
ON DismissedEmployees
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE e
    SET e.DismissDate = i.DismissDate
    FROM Employees e
    INNER JOIN inserted i ON e.ID = i.EmployeeID;
END;
GO

-- увольняем Senior Dev нанятых c 06.24 по 01.25
INSERT INTO DismissedEmployees (EmployeeID, DismissDate, DismissalReasonID)
SELECT 
    ID, 
    '2026-03-15',
    4
FROM Employees
WHERE (PositionID = 202 AND HireDate BETWEEN '20240601' AND '20250101');
GO

-- увольняем Middle Dev нанятых 03.23 по 03.24
INSERT INTO DismissedEmployees (EmployeeID, DismissDate, DismissalReasonID)
SELECT 
    ID, 
    '2026-03-15',
    3
FROM Employees
WHERE (PositionID = 203 AND HireDate BETWEEN '20230301' AND '20240301');
GO


-- 1. Очищаем историю полностью
DELETE FROM SalaryHistory;
GO
-- 2. Сбрасываем счетчик ID (чтобы история снова началась с 1)
DBCC CHECKIDENT ('SalaryHistory', RESEED, 0);
GO
-- 3. Заполняем заново
INSERT INTO SalaryHistory (EmployeeID, SalaryAmount, BonusPercent, DateFrom, DateTo)
SELECT ID, Salary, BonusPercent, HireDate, NULL
FROM Employees;
GO


-- #8 Добавляем процесс повышения сотрудника и повысим IT-шников со стажем от 3 лет

ALTER TABLE SalaryHistory ADD PositionID int;
GO

UPDATE sh SET sh.PositionID = e.PositionID 
FROM SalaryHistory sh JOIN Employees e ON sh.EmployeeID = e.ID;
GO

ALTER TRIGGER trg_Employees_UpdateSalary
ON Employees
AFTER UPDATE
AS
BEGIN
    -- срабатывает, если изменилась ЗП, Бонус ИЛИ Должность
    IF NOT (UPDATE(Salary) OR UPDATE(BonusPercent) OR UPDATE(PositionID)) RETURN;

    UPDATE sh SET sh.DateTo = DATEADD(day, -1, CAST(GETDATE() AS DATE))
    FROM SalaryHistory sh INNER JOIN deleted d ON sh.EmployeeID = d.ID
    WHERE sh.DateTo IS NULL;

    INSERT INTO SalaryHistory (EmployeeID, SalaryAmount, BonusPercent, PositionID, DateFrom, DateTo)
    SELECT i.ID, i.Salary, i.BonusPercent, i.PositionID, CAST(GETDATE() AS DATE), NULL
    FROM inserted i;
END;
GO

-- повышаем до Senior Dev
UPDATE e 
SET 
    PositionID = 202,
    Salary = 4000
FROM Employees e
WHERE PositionID = 203 AND DATEDIFF(YEAR, e.HireDate, GETDATE()) > 2;
GO

-- #9 Заплатим нашим сотрудникам за 26Q1 и дадим годовую премию Сидору :) !!! До UPDATE Salary !!!

DECLARE @Months TABLE (M_Date DATE, P_Date DATE);
INSERT INTO @Months VALUES
('2025-12-31', '2026-01-05'),
('2026-01-31', '2026-02-05'),
('2026-02-28', '2026-03-05'),
('2026-03-31', '2026-04-05');

-- выплатим ЗП
INSERT INTO Payroll (EmployeeID, Type, Amount, PaymentDate)
SELECT e.ID, 'Salary', e.Salary, m.P_Date
FROM Employees e
CROSS JOIN @Months m -- Аналог декартового произведения
WHERE e.HireDate <= m.P_Date
    AND (e.DismissDate IS NULL OR e.DismissDate >= m.P_Date);

-- выплатим Премии
INSERT INTO Payroll (EmployeeID, Type, Amount, PaymentDate, BonusTypeID)
SELECT e.ID, 'Bonus', (e.Salary * e.BonusPercent / 100.0), DATEADD(day, 5, m.P_Date), 1
FROM Employees e
CROSS JOIN @Months m
WHERE e.HireDate <= m.P_Date
    AND (e.DismissDate IS NULL OR e.DismissDate >= m.P_Date);
GO

-- выплатим годовой бонус мастодонту IT в нашей компании
INSERT INTO Payroll (EmployeeID, Type, Amount, PaymentDate, BonusTypeID)
VALUES (3, 'Bonus', 3000, '2026-01-16', 3);
GO


-- #10 Созданим витрину сотрудников и скорректируем их ЗП
CREATE VIEW View_Employees_Analytical_Core
AS
SELECT 
    e.ID AS Employee_ID,
    -- Склеиваем полное имя
    e.LastName + ' ' + e.FirstName + ' ' + ISNULL(e.MiddleName, '') AS Full_Name,
    e.Email,
    -- Данные о должности и отделе (джойним через Positions)
    p.Name AS Position_Name,
    d.Name AS Department_Name,
    -- Данные о руководителе (Self-Join)
    ISNULL(m.LastName + ' ' + LEFT(m.FirstName, 1) + '.', N'Топ-менеджмент') AS Manager_Short_Name,
    -- Текущие деньги
    e.Salary AS Current_Salary,
    e.BonusPercent AS Bonus_Percent,
    -- Расчетные аналитические поля
    DATEDIFF(YEAR, e.Birthday, GETDATE()) AS Age,
    DATEDIFF(YEAR, e.HireDate, GETDATE()) AS Seniority_Years,
    e.HireDate AS Hire_Date,
    CASE WHEN e.DismissDate IS NULL THEN N'Работает' ELSE N'Уволен' END AS Status
FROM Employees e
LEFT JOIN Positions p ON e.PositionID = p.ID
LEFT JOIN Departments d ON p.DepartmentID = d.ID -- Связь через таблицу позиций
LEFT JOIN Employees m ON e.ManagerID = m.ID; -- Self-Join для получения руководителя
GO

SELECT * FROM View_Employees_Analytical_Core
ORDER BY Hire_Date
GO

-- корректируем ЗП у сотрудников по вкладу и стажу
UPDATE e
SET Salary = CASE
    WHEN ID = 1 OR ID = 2 OR ID = 4 THEN 6000
    WHEN ID = 3 THEN 7000
    WHEN ID = 5 OR ID = 6 THEN 5500
    WHEN DATEDIFF(YEAR, e.HireDate, GETDATE()) >= 1 AND DATEDIFF(YEAR, e.HireDate, GETDATE()) < 2 THEN Salary + 200
    WHEN DATEDIFF(YEAR, e.HireDate, GETDATE()) >= 2 AND DATEDIFF(YEAR, e.HireDate, GETDATE()) < 3 THEN Salary + 400
    WHEN DATEDIFF(YEAR, e.HireDate, GETDATE()) >= 3 AND DATEDIFF(YEAR, e.HireDate, GETDATE()) < 4 THEN Salary + 600
    WHEN DATEDIFF(YEAR, e.HireDate, GETDATE()) >= 4 THEN Salary + 800
    ELSE Salary
END
FROM Employees e
WHERE DismissDate IS NULL;
GO


-- #11 Заплатим за Q2 (Новая ЗП) - после UPDATE Salary
DECLARE @NextMonths TABLE (M_Date DATE, P_Date DATE);
INSERT INTO @NextMonths VALUES
('2026-04-30', '2026-05-05'),
('2026-05-31', '2026-06-05'),
('2026-06-30', '2026-07-05');

-- выплатим новую ЗП
INSERT INTO Payroll (EmployeeID, Type, Amount, PaymentDate)
SELECT e.ID, 'Salary', e.Salary, m.P_Date
FROM Employees e
CROSS JOIN @NextMonths m
WHERE e.HireDate <= m.P_Date
    AND (e.DismissDate IS NULL OR e.DismissDate >= m.P_Date);

-- выплатим новую премию
INSERT INTO Payroll (EmployeeID, Type, Amount, PaymentDate, BonusTypeID)
SELECT e.ID, 'Bonus', (e.Salary * e.BonusPercent / 100.0), DATEADD(day, 5, m.P_Date), 1
FROM Employees e
CROSS JOIN @NextMonths m
WHERE e.HireDate <= m.P_Date
    AND (e.DismissDate IS NULL OR e.DismissDate >= m.P_Date);
GO


-- Проверка на выплаты уволенным сотрудникам
SELECT * FROM View_Employees_Analytical_Core
WHERE Status = 'Уволен'
ORDER BY Hire_Date
GO

SELECT * FROM Payroll
WHERE EmployeeID = 40
ORDER BY PaymentDate;
GO