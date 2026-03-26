USE Staff_DB;
GO

SET NOCOUNT ON;
GO


-- РАЗДЕЛ 1:
-- Обзор данных
GO

-- 1.1. Общая статистика базы
SELECT 
    (SELECT COUNT(*) FROM Employees WHERE DismissDate IS NULL) AS [Сотрудники в штате],
    (SELECT COUNT(*) FROM Employees WHERE DismissDate IS NOT NULL) AS [Уволенные сотрудники],
    (SELECT COUNT(*) FROM Payroll) AS [Всего выплат],
    (SELECT MIN(PaymentDate) FROM Payroll) AS [Первая выплата],
    (SELECT MAX(PaymentDate) FROM Payroll) AS [Крайняя выплата];
GO

-- 1.2. Таблица выплат
SELECT TOP 5 * FROM Payroll ORDER BY PaymentDate DESC;
GO

-- 1.3. Таблица увольнений (Триггер автоматически копируют информацию об увольнении в основную таблицу Employees)
SELECT TOP 5 * FROM DismissedEmployees ORDER BY DismissDate DESC;
GO

-- 1.4. Аналитическая витрина сотрудников (Основной инструмент для JOIN-ов в отчетах)
SELECT TOP 5 * FROM View_Employees_Analytical_Core;
GO


-- РАЗДЕЛ 2:
-- Аналитика данных
GO

-- CashFlow аналитика ЗП по отделам Q2/Q1
WITH QuarterlyCashOut AS (
    SELECT 
        d.Name AS Department_Name,
        DATETRUNC(quarter, p.PaymentDate) AS CalendarQuarter,
        COUNT(DISTINCT EmployeeID) AS Staff_Count, 
        SUM(p.Amount) AS Total_CashOut
    FROM Payroll p
    JOIN Employees e ON p.EmployeeID = e.ID
    JOIN Positions pos ON e.PositionID = pos.ID
    JOIN Departments d ON pos.DepartmentID = d.ID
    GROUP BY d.Name, DATETRUNC(quarter, p.PaymentDate)
),
CashFlowAnalytics AS (
    SELECT 
        Department_Name,
        CalendarQuarter,
        Staff_Count,
        CAST(Total_CashOut AS INT) AS Quarter_Outflow,

        CAST(
            (Total_CashOut * 1.0 / NULLIF(LAG(Total_CashOut) OVER(PARTITION BY Department_Name ORDER BY CalendarQuarter), 0)) - 1 
        AS decimal(10,2)) AS QoQ_rate

    FROM QuarterlyCashOut
)
SELECT 
    Department_Name,
    Staff_Count AS [Кол-во сотрудников],
    Quarter_Outflow AS Q2_Total,
    QoQ_rate,

    CAST(
        (Quarter_Outflow / 3.0) / ISNULL(Staff_Count, 0)
    AS INT) AS [Средняя ЗП (мес/чел)],
    
    CAST(
        Quarter_Outflow * 1.0 / SUM(Quarter_Outflow) OVER(PARTITION BY CalendarQuarter)
    AS decimal(10,2)) AS Budget_Share

FROM CashFlowAnalytics
WHERE CalendarQuarter = '2026-04-01'
ORDER BY Q2_Total DESC;
GO

-- Churn Rate отделов
WITH DeptStats AS (
    SELECT
        d.Name AS Department,
        COUNT(e.ID) AS TotalEver,
        COUNT(e.DismissDate) AS TotalDismissed
    FROM Employees e
    JOIN Positions p ON e.PositionID = p.ID
    JOIN Departments d ON p.DepartmentID = d.ID
    GROUP BY d.Name
)
SELECT 
    Department,
    TotalEver,
    TotalDismissed,
    CAST(TotalDismissed * 1.0 / TotalEver AS decimal(10, 2)) AS ChurnRate
FROM DeptStats
ORDER BY ChurnRate DESC; -- c самых проблемных отделов
GO

-- HR аналитика ЗП по отделам Q2/Q1
WITH QuarterMapping AS (
    SELECT 
        EmployeeID,
        Amount,
        CASE
            WHEN PaymentDate BETWEEN '20260201' AND '20260430' THEN 'Q1'
            WHEN PaymentDate BETWEEN '20260501' AND '20260731' THEN 'Q2'
            ELSE 'Other'
        END AS CustomQuarter
    FROM Payroll
),
QuarterAnalytics AS (
    SELECT
        d.Name AS Department_Name,
        qm.CustomQuarter,
        SUM(qm.Amount) AS QuarterTotal,
        COUNT(DISTINCT qm.EmployeeID) AS Staff_Count
    FROM QuarterMapping qm
    JOIN Employees e ON qm.EmployeeID = e.ID
    JOIN Positions pos ON e.PositionID = pos.ID
    JOIN Departments d ON pos.DepartmentID = d.ID
    GROUP BY d.Name, qm.CustomQuarter
),
FinalStats AS (
    SELECT
        qa.Department_Name,
        qa.CustomQuarter,
        CAST(qa.QuarterTotal AS INT) AS Q2_Total,
        qa.Staff_Count,

        CAST(
            (qa.QuarterTotal / 3.0) / NULLIF(qa.Staff_Count,0)
        AS INT) AS Avg_Monthly_Salary,

        CAST(
            (qa.QuarterTotal * 1.0 / NULLIF(LAG(qa.QuarterTotal) OVER(PARTITION BY qa.Department_Name ORDER BY qa.CustomQuarter), 0)) - 1
        AS decimal(10,2)) AS QoQ_rate
    FROM QuarterAnalytics qa

)
SELECT
    fs.Department_Name,
    fs.Staff_Count AS [Кол-во сотрудников],
    fs.Q2_Total,
    fs.QoQ_rate,
    fs.Avg_Monthly_Salary AS [Средняя ЗП (мес/чел)],

    CAST(
        fs.Q2_Total * 1.0 / SUM(fs.Q2_Total) OVER(PARTITION BY fs.CustomQuarter)
    AS decimal(10,2)) AS Budget_Share

FROM FinalStats fs
WHERE fs.CustomQuarter = 'Q2'
ORDER BY fs.Q2_Total DESC;
GO

-- HR аналитика ЗП по сотрудникам Q2/Q1
WITH QuarterMapping AS (
    SELECT 
        EmployeeID,
        Amount,
        CASE
            WHEN PaymentDate BETWEEN '20260201' AND '20260430' THEN 'Q1'
            WHEN PaymentDate BETWEEN '20260501' AND '20260731' THEN 'Q2'
            ELSE 'Other'
        END AS CustomQuarter
    FROM Payroll
),
QuarterAnalytics AS (
    SELECT
        EmployeeID,
        CustomQuarter,
        SUM(Amount) AS QuarterTotal
    FROM QuarterMapping
    GROUP BY EmployeeID, CustomQuarter
),
FinalStats AS (
    SELECT
        qa.EmployeeID,
        qa.CustomQuarter,
        CAST(qa.QuarterTotal AS INT) AS Q2_Total,

        CAST(
            (qa.QuarterTotal * 1.0 / NULLIF(LAG(qa.QuarterTotal) OVER(PARTITION BY qa.EmployeeID ORDER BY qa.CustomQuarter), 0)) - 1
        AS decimal(10,2)) AS QoQ_rate
    FROM QuarterAnalytics qa
)
SELECT
    e.Full_Name,
    e.Department_Name,
    e.Position_Name,
    e.Seniority_Years,
    fs.Q2_Total,
    fs.QoQ_rate,

    CASE NTILE(4) OVER(PARTITION BY fs.CustomQuarter ORDER BY fs.Q2_Total DESC)
        WHEN 1 THEN N'Топ-25% (Лидеры)'
        WHEN 2 THEN N'Выше среднего'
        WHEN 3 THEN N'Ниже среднего'
        ELSE N'Бюджетная группа'
    END AS Salary_Segment,

    CAST(
        fs.Q2_Total * 1.0 / SUM(fs.Q2_Total) OVER(PARTITION BY e.Department_Name, fs.CustomQuarter)
    AS decimal(10,2)) AS Dept_Budget_Share

FROM FinalStats fs
JOIN View_Employees_Analytical_Core e ON fs.EmployeeID = e.Employee_ID
WHERE fs.Q2_Total > 0 AND fs.CustomQuarter = 'Q2'
ORDER BY e.Department_Name, fs.Q2_Total DESC;
GO
