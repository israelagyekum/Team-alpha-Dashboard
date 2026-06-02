-- =====================================================================
-- DSCD 606 - Practical Mini Project
-- Governed Academic Data Management System (GADMS)
-- COMPLETE IMPLEMENTATION  (PostgreSQL 13+)
--
-- This single script:
--   1. Drops & recreates the full 12-table schema with constraints
--   2. Loads governed REFERENCE data (departments, programmes, courses,
--      lecturers, semester, course offerings)
--   3. Loads the REAL operational dataset supplied with the project:
--        - 100 students          - 302 enrollments
--        - 302 assessment results- 100 fee payments
--        - 500 LMS activity events
--   4. Creates indexes, a grading helper view, integrity-check queries
--      and the institutional analytics queries.
--
-- Run order is FK-safe.  Re-runnable (idempotent drops at top).
-- =====================================================================

SET client_min_messages = WARNING;

-- ---------------------------------------------------------------------
-- 0. Clean slate (reverse dependency order)
-- ---------------------------------------------------------------------
DROP VIEW  IF EXISTS v_student_grade_summary CASCADE;
DROP TABLE IF EXISTS LMSActivity       CASCADE;
DROP TABLE IF EXISTS FeePayment        CASCADE;
DROP TABLE IF EXISTS AssessmentResult  CASCADE;
DROP TABLE IF EXISTS Enrollment        CASCADE;
DROP TABLE IF EXISTS CourseOffering    CASCADE;
DROP TABLE IF EXISTS Admission         CASCADE;
DROP TABLE IF EXISTS Student           CASCADE;
DROP TABLE IF EXISTS Semester          CASCADE;
DROP TABLE IF EXISTS Lecturer          CASCADE;
DROP TABLE IF EXISTS Course            CASCADE;
DROP TABLE IF EXISTS Programme         CASCADE;
DROP TABLE IF EXISTS Department        CASCADE;

-- =====================================================================
-- 1. SCHEMA (DDL)  - 3NF, fully constrained
-- =====================================================================

CREATE TABLE Department (
    DepartmentID    SERIAL PRIMARY KEY,
    DepartmentName  VARCHAR(100) NOT NULL UNIQUE,
    Faculty         VARCHAR(100) NOT NULL,
    OfficeLocation  VARCHAR(100)
);

CREATE TABLE Programme (
    ProgrammeID    SERIAL PRIMARY KEY,
    DepartmentID   INT NOT NULL REFERENCES Department(DepartmentID),
    ProgrammeCode  VARCHAR(10) NOT NULL UNIQUE,
    ProgrammeName  VARCHAR(100) NOT NULL,
    DegreeType     VARCHAR(50) CHECK (DegreeType IN ('BSc','MSc','MPhil','PhD','Diploma')),
    DurationYears  INT CHECK (DurationYears > 0)
);

CREATE TABLE Course (
    CourseID      SERIAL PRIMARY KEY,
    DepartmentID  INT NOT NULL REFERENCES Department(DepartmentID),
    CourseCode    VARCHAR(10) NOT NULL UNIQUE,
    CourseTitle   VARCHAR(150) NOT NULL,
    CreditHours   INT CHECK (CreditHours BETWEEN 1 AND 6)
);

CREATE TABLE Lecturer (
    LecturerID    VARCHAR(15) PRIMARY KEY,
    DepartmentID  INT NOT NULL REFERENCES Department(DepartmentID),
    LecturerName  VARCHAR(100) NOT NULL,
    Rank          VARCHAR(50),
    Email         VARCHAR(100) UNIQUE
);

CREATE TABLE Semester (
    SemesterID    SERIAL PRIMARY KEY,
    SemesterName  VARCHAR(40) NOT NULL,
    StartDate     DATE NOT NULL,
    EndDate       DATE NOT NULL,
    CHECK (EndDate > StartDate)
);

CREATE TABLE Student (
    StudentID     VARCHAR(15) PRIMARY KEY,
    ProgrammeID   INT NOT NULL REFERENCES Programme(ProgrammeID),
    FirstName     VARCHAR(50) NOT NULL,
    LastName      VARCHAR(50) NOT NULL,
    Gender        VARCHAR(10) CHECK (Gender IN ('Male','Female','Other')),
    DateOfBirth   DATE,
    Email         VARCHAR(100) UNIQUE,
    PhoneNumber   VARCHAR(20),
    AdmissionYear INT CHECK (AdmissionYear BETWEEN 2000 AND 2100),
    Status        VARCHAR(20) DEFAULT 'Active'
        CHECK (Status IN ('Active','Suspended','Graduated','Withdrawn'))
);

CREATE TABLE Admission (
    AdmissionID     SERIAL PRIMARY KEY,
    ProgrammeID     INT NOT NULL REFERENCES Programme(ProgrammeID),
    ApplicantName   VARCHAR(150) NOT NULL,
    AdmissionDate   DATE NOT NULL DEFAULT CURRENT_DATE,
    AdmissionStatus VARCHAR(20)
        CHECK (AdmissionStatus IN ('Pending','Admitted','Rejected'))
);

CREATE TABLE CourseOffering (
    CourseOfferingID SERIAL PRIMARY KEY,
    CourseID         INT NOT NULL REFERENCES Course(CourseID),
    LecturerID       VARCHAR(15) NOT NULL REFERENCES Lecturer(LecturerID),
    SemesterID       INT NOT NULL REFERENCES Semester(SemesterID),
    AcademicYear     VARCHAR(9) NOT NULL,
    UNIQUE (CourseID, SemesterID, AcademicYear)
);

CREATE TABLE Enrollment (
    EnrollmentID     SERIAL PRIMARY KEY,
    StudentID        VARCHAR(15) NOT NULL REFERENCES Student(StudentID),
    CourseOfferingID INT NOT NULL REFERENCES CourseOffering(CourseOfferingID),
    EnrollmentDate   DATE NOT NULL DEFAULT CURRENT_DATE,
    EnrollmentStatus VARCHAR(20) DEFAULT 'Active'
        CHECK (EnrollmentStatus IN ('Active','Dropped','Completed','Failed')),
    UNIQUE (StudentID, CourseOfferingID)
);

CREATE TABLE AssessmentResult (
    ResultID        SERIAL PRIMARY KEY,
    EnrollmentID    INT NOT NULL UNIQUE REFERENCES Enrollment(EnrollmentID),
    CourseworkScore DECIMAL(5,2) CHECK (CourseworkScore BETWEEN 0 AND 100),
    ExamScore       DECIMAL(5,2) CHECK (ExamScore BETWEEN 0 AND 100),
    FinalGrade      CHAR(2) CHECK (FinalGrade IN ('A','B+','B','C+','C','D+','D','F','I'))
);

CREATE TABLE FeePayment (
    PaymentID     SERIAL PRIMARY KEY,
    StudentID     VARCHAR(15) NOT NULL REFERENCES Student(StudentID),
    AmountPaid    DECIMAL(10,2) NOT NULL CHECK (AmountPaid >= 0),
    PaymentDate   DATE NOT NULL DEFAULT CURRENT_DATE,
    PaymentMethod VARCHAR(30)
        CHECK (PaymentMethod IN ('Bank','Mobile Money','Card','Cash')),
    Balance       DECIMAL(10,2)
);

CREATE TABLE LMSActivity (
    ActivityID       BIGSERIAL PRIMARY KEY,
    StudentID        VARCHAR(15) NOT NULL REFERENCES Student(StudentID),
    CourseOfferingID INT REFERENCES CourseOffering(CourseOfferingID),
    LoginTimestamp   TIMESTAMP NOT NULL,
    ActivityType     VARCHAR(50)
        CHECK (ActivityType IN ('Login','PageView','QuizAttempt','AssignmentUpload','Forum')),
    DurationMinutes  INT CHECK (DurationMinutes >= 0)
);

-- =====================================================================
-- 2. REFERENCE / MASTER DATA
--    (governed institutional data the operational CSVs depend on)
-- =====================================================================

INSERT INTO Department (DepartmentID, DepartmentName, Faculty, OfficeLocation) VALUES
 (1, 'Computer Science', 'Physical and Mathematical Sciences', 'Block A'),
 (2, 'Statistics and Actuarial Science', 'Physical and Mathematical Sciences', 'Block C');
SELECT setval('department_departmentid_seq', 2, true);

-- ProgrammeIDs 1-4 are referenced by the student dataset
INSERT INTO Programme (ProgrammeID, DepartmentID, ProgrammeCode, ProgrammeName, DegreeType, DurationYears) VALUES
 (1, 1, 'DSC-MP', 'MPhil Data Science',         'MPhil', 2),
 (2, 1, 'DSC-MS', 'MSc Data Science',           'MSc',   2),
 (3, 1, 'CS-MS',  'MSc Computer Science',       'MSc',   2),
 (4, 1, 'CS-BS',  'BSc Computer Science',       'BSc',   4);
SELECT setval('programme_programmeid_seq', 4, true);

-- 5 courses -> 5 offerings (CourseOfferingID 1-5 referenced by enrollments & LMS)
INSERT INTO Course (CourseID, DepartmentID, CourseCode, CourseTitle, CreditHours) VALUES
 (1, 1, 'DSCD606', 'Data Management Techniques', 3),
 (2, 1, 'DSCD604', 'Machine Learning',           3),
 (3, 1, 'DSCD602', 'Statistical Computing',      3),
 (4, 1, 'DSCD601', 'Foundations of Data Science',3),
 (5, 1, 'DSCD603', 'Big Data Analytics',         3);
SELECT setval('course_courseid_seq', 5, true);

INSERT INTO Lecturer (LecturerID, DepartmentID, LecturerName, Rank, Email) VALUES
 ('LEC001', 1, 'Prof. Kofi Sarpong Adu-Manu', 'Professor',           'ksamanu@ug.edu.gh'),
 ('LEC002', 1, 'Dr. Akosua Owusu',            'Senior Lecturer',     'aowusu@ug.edu.gh'),
 ('LEC003', 2, 'Dr. Yaw Mensah',              'Lecturer',            'ymensah@ug.edu.gh');

INSERT INTO Semester (SemesterID, SemesterName, StartDate, EndDate) VALUES
 (1, 'Semester 1 2025/2026', '2026-01-13', '2026-05-30');
SELECT setval('semester_semesterid_seq', 1, true);

INSERT INTO CourseOffering (CourseOfferingID, CourseID, LecturerID, SemesterID, AcademicYear) VALUES
 (1, 1, 'LEC001', 1, '2025/2026'),
 (2, 2, 'LEC002', 1, '2025/2026'),
 (3, 3, 'LEC003', 1, '2025/2026'),
 (4, 4, 'LEC001', 1, '2025/2026'),
 (5, 5, 'LEC002', 1, '2025/2026');
SELECT setval('courseoffering_courseofferingid_seq', 5, true);


-- ---------------------------------------------------------------------
-- 3. OPERATIONAL DATA  (loaded from supplied CSV datasets)
-- ---------------------------------------------------------------------

-- 3.1 Students (100 rows)
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026001', 2, 'Christopher', 'Lowe', 'Female', '1999-03-16', 'christopher.lowe1@st.ug.edu.gh', '0796864536', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026002', 3, 'Kelly', 'Alexander', 'Female', '2003-12-10', 'kelly.alexander2@st.ug.edu.gh', '0309715044', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026003', 1, 'Joseph', 'Kelly', 'Male', '2005-12-03', 'joseph.kelly3@st.ug.edu.gh', '0934015747', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026004', 1, 'Willie', 'Lee', 'Male', '1993-06-06', 'willie.lee4@st.ug.edu.gh', '0026902016', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026005', 1, 'Bradley', 'Bailey', 'Male', '2002-02-14', 'bradley.bailey5@st.ug.edu.gh', '0113108481', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026006', 3, 'Laura', 'Stokes', 'Male', '1999-01-14', 'laura.stokes6@st.ug.edu.gh', '0235696938', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026007', 4, 'Paul', 'Hester', 'Male', '2002-11-24', 'paul.hester7@st.ug.edu.gh', '0654569629', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026008', 3, 'Kathleen', 'Howard', 'Male', '2005-10-08', 'kathleen.howard8@st.ug.edu.gh', '0147130949', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026009', 2, 'Peter', 'Jackson', 'Male', '1997-10-24', 'peter.jackson9@st.ug.edu.gh', '0164969102', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026010', 4, 'Melinda', 'Camacho', 'Female', '1996-01-20', 'melinda.camacho10@st.ug.edu.gh', '0352273484', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026011', 1, 'Walter', 'Stanley', 'Male', '1995-09-10', 'walter.stanley11@st.ug.edu.gh', '0262053769', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026012', 3, 'William', 'Ewing', 'Male', '1991-08-25', 'william.ewing12@st.ug.edu.gh', '0913410854', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026013', 2, 'Robert', 'Howard', 'Female', '1999-04-12', 'robert.howard13@st.ug.edu.gh', '0690783095', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026014', 1, 'Scott', 'Rice', 'Male', '2002-09-12', 'scott.rice14@st.ug.edu.gh', '0517357450', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026015', 1, 'Isaac', 'Harris', 'Female', '1994-06-26', 'isaac.harris15@st.ug.edu.gh', '0736864374', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026016', 4, 'Sarah', 'Moore', 'Male', '1991-11-07', 'sarah.moore16@st.ug.edu.gh', '0491642977', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026017', 4, 'Megan', 'Cooper', 'Female', '1995-11-21', 'megan.cooper17@st.ug.edu.gh', '0519032179', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026018', 1, 'George', 'Patterson', 'Male', '2004-01-14', 'george.patterson18@st.ug.edu.gh', '0341484864', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026019', 3, 'Michael', 'Berry', 'Female', '1995-06-10', 'michael.berry19@st.ug.edu.gh', '0637220726', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026020', 2, 'Evan', 'Fernandez', 'Male', '1998-12-12', 'evan.fernandez20@st.ug.edu.gh', '0680217891', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026021', 3, 'Thomas', 'Sweeney', 'Female', '2006-02-25', 'thomas.sweeney21@st.ug.edu.gh', '0715982403', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026022', 2, 'Barbara', 'Myers', 'Male', '1999-01-11', 'barbara.myers22@st.ug.edu.gh', '0404352205', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026023', 1, 'James', 'Kelly', 'Male', '1997-10-19', 'james.kelly23@st.ug.edu.gh', '0585106776', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026024', 2, 'Cathy', 'Gilbert', 'Female', '1999-12-17', 'cathy.gilbert24@st.ug.edu.gh', '0291872284', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026025', 3, 'April', 'Wheeler', 'Male', '1998-08-15', 'april.wheeler25@st.ug.edu.gh', '0268157757', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026026', 3, 'David', 'Terry', 'Male', '1995-04-10', 'david.terry26@st.ug.edu.gh', '0578848081', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026027', 1, 'Shawn', 'Brown', 'Female', '1999-06-05', 'shawn.brown27@st.ug.edu.gh', '0038093544', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026028', 2, 'Kevin', 'Jones', 'Female', '1993-08-03', 'kevin.jones28@st.ug.edu.gh', '0228778667', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026029', 1, 'Lucas', 'Trevino', 'Female', '2002-12-23', 'lucas.trevino29@st.ug.edu.gh', '0742711411', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026030', 1, 'Pamela', 'Smith', 'Male', '2005-01-13', 'pamela.smith30@st.ug.edu.gh', '0896466594', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026031', 2, 'Michael', 'Waters', 'Female', '1992-04-27', 'michael.waters31@st.ug.edu.gh', '0381043869', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026032', 1, 'Karen', 'Rodriguez', 'Female', '1991-10-05', 'karen.rodriguez32@st.ug.edu.gh', '0603135338', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026033', 2, 'Alyssa', 'Hubbard', 'Male', '2005-06-02', 'alyssa.hubbard33@st.ug.edu.gh', '0757275679', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026034', 3, 'Brandon', 'Farrell', 'Male', '1996-05-08', 'brandon.farrell34@st.ug.edu.gh', '0292793224', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026035', 2, 'Kenneth', 'Castillo', 'Male', '1991-10-15', 'kenneth.castillo35@st.ug.edu.gh', '0064033056', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026036', 1, 'Cheryl', 'Pittman', 'Male', '1992-01-08', 'cheryl.pittman36@st.ug.edu.gh', '0090317133', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026037', 1, 'Sara', 'Gomez', 'Female', '1993-10-13', 'sara.gomez37@st.ug.edu.gh', '0797854830', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026038', 1, 'Hannah', 'Ortiz', 'Female', '1996-07-23', 'hannah.ortiz38@st.ug.edu.gh', '0588864015', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026039', 1, 'Blake', 'Guzman', 'Male', '1992-08-11', 'blake.guzman39@st.ug.edu.gh', '0395991576', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026040', 3, 'Jonathan', 'Boone', 'Male', '1995-04-19', 'jonathan.boone40@st.ug.edu.gh', '0561839595', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026041', 4, 'Vincent', 'Hanson', 'Female', '2002-03-02', 'vincent.hanson41@st.ug.edu.gh', '0372076431', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026042', 4, 'James', 'Bright', 'Male', '2005-03-02', 'james.bright42@st.ug.edu.gh', '0979559870', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026043', 1, 'Bryan', 'Bruce', 'Female', '1995-04-07', 'bryan.bruce43@st.ug.edu.gh', '0828891176', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026044', 3, 'Laura', 'Gray', 'Female', '1994-02-04', 'laura.gray44@st.ug.edu.gh', '0192799654', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026045', 4, 'Tanya', 'Wilkerson', 'Male', '1998-12-02', 'tanya.wilkerson45@st.ug.edu.gh', '0281100644', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026046', 3, 'Brittany', 'Mitchell', 'Female', '1993-02-17', 'brittany.mitchell46@st.ug.edu.gh', '0730924055', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026047', 1, 'Cynthia', 'Robinson', 'Male', '2001-04-29', 'cynthia.robinson47@st.ug.edu.gh', '0477234718', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026048', 1, 'Julie', 'Berry', 'Male', '2000-09-07', 'julie.berry48@st.ug.edu.gh', '0020037450', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026049', 2, 'Rebecca', 'Wood', 'Male', '2001-10-06', 'rebecca.wood49@st.ug.edu.gh', '0447942813', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026050', 1, 'Sarah', 'Oneill', 'Male', '1994-07-27', 'sarah.oneill50@st.ug.edu.gh', '0926124130', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026051', 4, 'Sheila', 'Pearson', 'Male', '1992-11-07', 'sheila.pearson51@st.ug.edu.gh', '0578545557', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026052', 2, 'Kayla', 'Griffin', 'Female', '1992-03-14', 'kayla.griffin52@st.ug.edu.gh', '0150573334', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026053', 1, 'Stephanie', 'Hicks', 'Female', '1998-07-16', 'stephanie.hicks53@st.ug.edu.gh', '0128801564', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026054', 4, 'Molly', 'Torres', 'Female', '2003-05-11', 'molly.torres54@st.ug.edu.gh', '0258016413', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026055', 2, 'Meagan', 'Obrien', 'Male', '2004-09-11', 'meagan.obrien55@st.ug.edu.gh', '0685861940', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026056', 1, 'Deborah', 'Molina', 'Male', '2002-03-28', 'deborah.molina56@st.ug.edu.gh', '0197310747', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026057', 2, 'Mark', 'Hanna', 'Female', '1997-04-17', 'mark.hanna57@st.ug.edu.gh', '0434627246', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026058', 1, 'Miranda', 'Long', 'Female', '2003-10-02', 'miranda.long58@st.ug.edu.gh', '0966658847', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026059', 1, 'Dawn', 'Williams', 'Female', '1992-10-09', 'dawn.williams59@st.ug.edu.gh', '0139495711', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026060', 3, 'Jeremy', 'Moore', 'Female', '1998-11-06', 'jeremy.moore60@st.ug.edu.gh', '0366831676', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026061', 1, 'Stephanie', 'Holland', 'Female', '1992-02-18', 'stephanie.holland61@st.ug.edu.gh', '0951129771', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026062', 3, 'Destiny', 'Lopez', 'Male', '2001-06-16', 'destiny.lopez62@st.ug.edu.gh', '0003268330', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026063', 1, 'Thomas', 'Robinson', 'Male', '2004-07-29', 'thomas.robinson63@st.ug.edu.gh', '0159882308', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026064', 1, 'Sarah', 'Williams', 'Male', '1992-11-18', 'sarah.williams64@st.ug.edu.gh', '0610257905', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026065', 1, 'Andrew', 'Bullock', 'Male', '2005-12-06', 'andrew.bullock65@st.ug.edu.gh', '0367703079', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026066', 1, 'Cameron', 'Johnson', 'Female', '1996-12-03', 'cameron.johnson66@st.ug.edu.gh', '0987475044', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026067', 2, 'Hannah', 'Howard', 'Female', '1996-09-14', 'hannah.howard67@st.ug.edu.gh', '0025711975', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026068', 2, 'Leslie', 'Ramos', 'Male', '2001-04-23', 'leslie.ramos68@st.ug.edu.gh', '0908082056', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026069', 3, 'Virginia', 'Cannon', 'Female', '1996-12-16', 'virginia.cannon69@st.ug.edu.gh', '0382667048', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026070', 1, 'Zachary', 'Fry', 'Male', '2004-05-31', 'zachary.fry70@st.ug.edu.gh', '0024888827', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026071', 3, 'Maria', 'Donovan', 'Male', '2006-01-15', 'maria.donovan71@st.ug.edu.gh', '0707494829', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026072', 2, 'Angela', 'Wilson', 'Male', '2002-04-05', 'angela.wilson72@st.ug.edu.gh', '0232754195', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026073', 2, 'Nathan', 'Meyer', 'Female', '2004-10-11', 'nathan.meyer73@st.ug.edu.gh', '0972851393', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026074', 1, 'Angelica', 'Mullins', 'Male', '2004-05-21', 'angelica.mullins74@st.ug.edu.gh', '0143109167', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026075', 3, 'Michael', 'Gomez', 'Male', '1995-05-03', 'michael.gomez75@st.ug.edu.gh', '0780245441', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026076', 3, 'Sylvia', 'Watkins', 'Female', '1999-06-17', 'sylvia.watkins76@st.ug.edu.gh', '0528444203', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026077', 3, 'Kyle', 'Jones', 'Male', '1991-08-04', 'kyle.jones77@st.ug.edu.gh', '0732563175', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026078', 2, 'Zachary', 'Gardner', 'Male', '2001-02-25', 'zachary.gardner78@st.ug.edu.gh', '0161426492', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026079', 1, 'Zoe', 'Lopez', 'Male', '2005-07-05', 'zoe.lopez79@st.ug.edu.gh', '0325291538', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026080', 1, 'Matthew', 'Byrd', 'Female', '1997-10-05', 'matthew.byrd80@st.ug.edu.gh', '0513976464', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026081', 4, 'Eric', 'Pope', 'Male', '2002-07-28', 'eric.pope81@st.ug.edu.gh', '0579042078', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026082', 1, 'Shannon', 'Sanders', 'Male', '2001-10-31', 'shannon.sanders82@st.ug.edu.gh', '0704274065', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026083', 1, 'Daniel', 'Hernandez', 'Male', '1991-06-05', 'daniel.hernandez83@st.ug.edu.gh', '0783753888', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026084', 2, 'Linda', 'Scott', 'Female', '1999-11-21', 'linda.scott84@st.ug.edu.gh', '0504110154', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026085', 2, 'Harry', 'Patel', 'Male', '2004-08-17', 'harry.patel85@st.ug.edu.gh', '0170659626', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026086', 2, 'Anna', 'Walker', 'Male', '1999-03-30', 'anna.walker86@st.ug.edu.gh', '0400363851', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026087', 2, 'Wendy', 'Rivera', 'Female', '2004-11-21', 'wendy.rivera87@st.ug.edu.gh', '0616318884', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026088', 2, 'Tara', 'Foster', 'Male', '2001-12-08', 'tara.foster88@st.ug.edu.gh', '0812081013', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026089', 2, 'Michael', 'Lawrence', 'Female', '1998-07-09', 'michael.lawrence89@st.ug.edu.gh', '0475098265', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026090', 2, 'Christian', 'Haney', 'Male', '1992-11-12', 'christian.haney90@st.ug.edu.gh', '0349678145', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026091', 2, 'Michael', 'Newton', 'Female', '1996-07-14', 'michael.newton91@st.ug.edu.gh', '0466368584', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026092', 1, 'Phillip', 'Mccoy', 'Male', '1994-05-15', 'phillip.mccoy92@st.ug.edu.gh', '0267985610', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026093', 3, 'Karen', 'Greene', 'Male', '1993-12-14', 'karen.greene93@st.ug.edu.gh', '0925605168', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026094', 1, 'Lisa', 'Duran', 'Female', '1997-01-30', 'lisa.duran94@st.ug.edu.gh', '0726456220', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026095', 2, 'Jennifer', 'Fritz', 'Female', '1992-07-29', 'jennifer.fritz95@st.ug.edu.gh', '0957776622', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026096', 1, 'Melissa', 'Martin', 'Female', '2004-04-08', 'melissa.martin96@st.ug.edu.gh', '0451722851', 2026, 'Graduated');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026097', 1, 'Emma', 'Johnson', 'Male', '2002-05-21', 'emma.johnson97@st.ug.edu.gh', '0713414757', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026098', 2, 'Emily', 'Huff', 'Female', '1993-06-22', 'emily.huff98@st.ug.edu.gh', '0366989451', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026099', 2, 'Brian', 'Austin', 'Female', '1996-09-01', 'brian.austin99@st.ug.edu.gh', '0543411817', 2026, 'Active');
INSERT INTO Student (StudentID, ProgrammeID, FirstName, LastName, Gender, DateOfBirth, Email, PhoneNumber, AdmissionYear, Status) VALUES ('UG2026100', 1, 'Lawrence', 'Jones', 'Male', '1999-09-04', 'lawrence.jones100@st.ug.edu.gh', '0935176960', 2026, 'Active');

-- 3.2 Enrollments (302 rows). Insert order fixes EnrollmentID = row number,
--     which the assessment_results dataset references by EnrollmentID.
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026001', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026001', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026001', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026002', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026002', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026003', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026003', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026004', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026004', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026004', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026005', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026005', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026006', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026006', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026006', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026007', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026007', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026007', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026007', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026008', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026008', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026008', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026009', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026009', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026010', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026010', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026011', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026011', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026011', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026011', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026012', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026012', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026012', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026012', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026013', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026013', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026013', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026014', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026014', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026014', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026015', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026015', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026015', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026015', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026016', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026016', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026017', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026017', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026018', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026018', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026018', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026019', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026019', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026019', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026019', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026020', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026020', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026021', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026021', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026022', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026022', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026022', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026023', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026023', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026024', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026024', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026025', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026025', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026025', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026026', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026026', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026026', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026027', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026027', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026028', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026028', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026028', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026029', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026029', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026029', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026029', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026030', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026030', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026030', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026031', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026031', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026031', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026032', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026032', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026033', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026033', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026034', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026034', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026035', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026035', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026035', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026035', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026036', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026036', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026036', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026036', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026037', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026037', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026038', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026038', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026038', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026038', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026039', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026039', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026039', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026040', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026040', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026040', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026040', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026041', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026041', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026042', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026042', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026043', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026043', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026043', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026043', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026044', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026044', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026044', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026044', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026045', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026045', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026045', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026045', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026046', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026046', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026046', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026047', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026047', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026047', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026047', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026048', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026048', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026048', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026048', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026049', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026049', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026049', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026050', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026050', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026051', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026051', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026051', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026051', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026052', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026052', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026052', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026053', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026053', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026054', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026054', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026055', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026055', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026055', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026055', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026056', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026056', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026057', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026057', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026057', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026058', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026058', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026058', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026058', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026059', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026059', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026059', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026060', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026060', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026060', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026060', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026061', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026061', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026061', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026062', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026062', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026063', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026063', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026064', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026064', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026064', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026064', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026065', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026065', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026065', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026066', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026066', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026066', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026066', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026067', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026067', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026067', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026068', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026068', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026068', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026069', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026069', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026070', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026070', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026070', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026070', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026071', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026071', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026072', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026072', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026072', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026072', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026073', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026073', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026073', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026073', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026074', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026074', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026074', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026075', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026075', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026075', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026076', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026076', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026076', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026076', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026077', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026077', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026077', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026077', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026078', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026078', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026078', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026079', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026079', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026079', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026079', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026080', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026080', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026080', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026080', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026081', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026081', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026082', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026082', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026083', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026083', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026083', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026083', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026084', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026084', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026085', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026085', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026085', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026085', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026086', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026086', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026086', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026086', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026087', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026087', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026087', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026088', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026088', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026088', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026089', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026089', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026090', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026090', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026090', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026090', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026091', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026091', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026092', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026092', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026092', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026092', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026093', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026093', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026093', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026094', 4, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026094', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026094', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026094', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026095', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026095', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026095', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026096', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026096', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026096', 1, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026097', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026097', 4, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026097', 5, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026097', 3, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026098', 3, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026098', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026098', 1, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026099', 5, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026099', 2, '2026-05-26', 'Completed');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026100', 2, '2026-05-26', 'Active');
INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus) VALUES ('UG2026100', 4, '2026-05-26', 'Active');
SELECT setval('enrollment_enrollmentid_seq', (SELECT MAX(EnrollmentID) FROM Enrollment), true);

-- 3.3 Assessment results (302 rows). FinalGrade kept as the authoritative
--     system-of-record value supplied by the Examinations Office dataset.
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (1, 89.01, 67.02, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (2, 94.87, 94.76, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (3, 85.15, 89.42, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (4, 77.54, 66.54, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (5, 90.81, 84.82, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (6, 56.24, 56.9, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (7, 81.67, 47.64, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (8, 60.05, 59.3, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (9, 71.02, 47.25, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (10, 74.91, 48.19, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (11, 61.41, 93.59, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (12, 53.5, 93.94, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (13, 76.72, 54.66, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (14, 73.14, 59.61, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (15, 53.4, 56.47, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (16, 52.29, 46.55, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (17, 51.48, 69.89, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (18, 61.27, 94.39, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (19, 86.55, 83.33, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (20, 69.8, 69.85, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (21, 84.53, 84.32, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (22, 84.99, 67.52, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (23, 87.09, 82.41, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (24, 73.94, 48.33, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (25, 55.36, 52.83, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (26, 86.62, 70.38, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (27, 94.83, 94.06, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (28, 62.21, 60.14, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (29, 82.08, 72.47, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (30, 73.35, 69.51, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (31, 79.46, 83.94, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (32, 79.04, 63.36, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (33, 76.73, 55.56, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (34, 89.46, 77.36, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (35, 84.26, 84.19, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (36, 50.21, 86.86, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (37, 78.81, 74.53, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (38, 83.43, 57.85, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (39, 85.65, 49.84, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (40, 84.05, 47.58, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (41, 90.86, 78.68, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (42, 51.5, 74.01, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (43, 56.3, 85.43, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (44, 78.1, 88.72, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (45, 88.74, 92.18, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (46, 75.84, 57.66, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (47, 57.79, 82.07, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (48, 75.52, 62.92, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (49, 81.23, 88.34, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (50, 89.19, 62.25, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (51, 73.88, 92.29, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (52, 79.78, 87.35, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (53, 51.05, 48.1, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (54, 84.84, 47.13, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (55, 63.82, 71.18, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (56, 85.46, 76.42, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (57, 53.96, 50.61, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (58, 78.81, 61.32, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (59, 73.32, 89.77, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (60, 61.7, 45.39, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (61, 55.55, 89.07, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (62, 78.41, 46.17, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (63, 69.47, 62.83, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (64, 73.95, 71.2, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (65, 85.28, 69.9, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (66, 76.9, 74.45, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (67, 61.8, 81.17, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (68, 86.86, 81.65, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (69, 70.39, 55.22, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (70, 59.34, 76.65, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (71, 87.08, 65.46, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (72, 58.21, 93.94, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (73, 62.92, 75.67, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (74, 55.87, 55.7, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (75, 84.7, 63.01, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (76, 73.53, 91.45, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (77, 66.33, 68.79, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (78, 50.2, 49.83, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (79, 56.12, 75.72, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (80, 70.18, 49.11, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (81, 63.29, 54.96, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (82, 50.9, 70.51, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (83, 83.83, 86.35, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (84, 68.22, 56.8, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (85, 51.34, 88.55, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (86, 68.21, 47.03, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (87, 69.9, 58.42, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (88, 53.49, 89.92, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (89, 69.05, 81.72, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (90, 88.41, 65.75, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (91, 93.07, 72.93, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (92, 51.57, 74.47, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (93, 91.86, 81.61, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (94, 58.16, 84.09, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (95, 55.19, 78.39, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (96, 85.28, 77.85, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (97, 94.82, 86.81, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (98, 61.71, 73.02, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (99, 64.86, 88.37, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (100, 61.9, 68.23, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (101, 57.34, 74.93, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (102, 93.08, 87.2, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (103, 64.84, 62.57, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (104, 80.0, 57.67, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (105, 56.75, 66.32, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (106, 68.4, 53.61, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (107, 72.14, 51.37, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (108, 79.17, 72.81, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (109, 55.71, 74.87, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (110, 72.92, 59.82, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (111, 79.65, 84.56, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (112, 92.73, 91.95, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (113, 60.82, 79.36, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (114, 58.51, 93.78, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (115, 93.28, 69.36, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (116, 61.7, 75.69, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (117, 53.54, 63.81, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (118, 52.04, 89.75, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (119, 51.86, 89.21, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (120, 62.52, 51.94, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (121, 71.76, 91.14, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (122, 83.29, 74.62, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (123, 74.79, 46.83, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (124, 53.26, 81.06, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (125, 72.92, 67.17, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (126, 68.81, 69.85, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (127, 81.66, 68.56, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (128, 57.58, 67.87, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (129, 70.39, 48.48, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (130, 78.54, 52.38, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (131, 86.34, 61.13, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (132, 61.08, 72.35, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (133, 60.99, 62.97, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (134, 84.47, 77.73, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (135, 88.47, 76.05, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (136, 83.78, 56.59, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (137, 62.23, 61.89, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (138, 57.67, 68.71, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (139, 66.86, 70.59, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (140, 90.38, 68.92, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (141, 77.44, 83.89, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (142, 80.72, 77.5, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (143, 90.09, 89.85, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (144, 83.96, 88.86, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (145, 54.69, 88.03, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (146, 74.03, 47.09, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (147, 53.69, 81.25, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (148, 70.53, 85.09, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (149, 55.46, 84.19, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (150, 89.03, 53.21, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (151, 55.86, 72.3, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (152, 81.72, 52.85, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (153, 80.38, 88.59, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (154, 68.76, 63.19, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (155, 79.21, 51.35, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (156, 59.02, 80.32, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (157, 90.38, 73.59, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (158, 70.63, 82.57, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (159, 67.1, 83.24, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (160, 82.33, 73.69, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (161, 88.53, 59.93, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (162, 86.1, 47.88, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (163, 55.38, 57.73, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (164, 87.61, 78.05, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (165, 83.55, 77.21, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (166, 83.11, 88.04, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (167, 51.93, 46.9, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (168, 59.57, 59.48, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (169, 65.52, 61.21, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (170, 67.96, 66.36, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (171, 68.63, 63.61, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (172, 62.86, 88.69, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (173, 59.12, 47.0, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (174, 72.5, 80.25, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (175, 82.69, 94.93, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (176, 75.88, 68.09, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (177, 85.82, 88.65, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (178, 78.97, 46.99, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (179, 52.15, 66.26, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (180, 64.68, 58.35, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (181, 64.5, 90.71, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (182, 77.65, 76.18, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (183, 56.8, 73.68, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (184, 77.65, 83.75, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (185, 90.49, 49.5, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (186, 87.98, 82.63, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (187, 72.06, 73.32, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (188, 59.28, 58.45, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (189, 80.88, 68.65, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (190, 51.34, 89.66, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (191, 57.91, 75.09, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (192, 89.18, 74.42, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (193, 57.36, 74.51, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (194, 56.53, 52.49, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (195, 83.62, 83.93, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (196, 67.79, 85.58, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (197, 88.28, 56.58, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (198, 71.92, 66.87, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (199, 57.83, 73.86, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (200, 55.18, 90.69, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (201, 56.43, 49.07, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (202, 58.65, 59.63, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (203, 55.95, 84.98, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (204, 84.22, 73.25, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (205, 88.26, 72.69, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (206, 92.6, 71.29, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (207, 92.42, 55.46, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (208, 53.77, 71.09, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (209, 83.86, 68.19, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (210, 73.89, 94.36, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (211, 83.4, 88.41, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (212, 82.06, 53.41, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (213, 59.64, 63.54, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (214, 70.52, 54.76, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (215, 92.5, 94.25, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (216, 63.93, 59.39, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (217, 58.15, 77.18, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (218, 75.04, 56.42, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (219, 50.73, 64.28, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (220, 87.37, 80.93, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (221, 76.76, 65.16, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (222, 54.93, 63.78, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (223, 88.99, 75.08, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (224, 63.54, 65.7, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (225, 59.69, 47.25, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (226, 51.71, 67.14, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (227, 93.67, 73.37, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (228, 58.25, 60.03, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (229, 91.54, 52.48, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (230, 79.77, 73.22, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (231, 68.22, 74.51, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (232, 73.05, 89.51, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (233, 93.72, 92.23, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (234, 57.75, 76.52, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (235, 94.32, 50.83, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (236, 89.97, 57.89, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (237, 61.05, 65.43, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (238, 76.32, 92.81, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (239, 65.89, 75.39, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (240, 77.94, 56.18, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (241, 89.23, 80.25, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (242, 59.18, 71.81, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (243, 93.14, 93.67, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (244, 66.01, 90.08, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (245, 94.75, 50.61, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (246, 53.26, 80.01, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (247, 78.94, 94.58, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (248, 74.76, 73.91, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (249, 56.47, 86.27, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (250, 72.85, 52.69, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (251, 61.24, 50.25, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (252, 56.97, 47.24, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (253, 77.89, 85.58, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (254, 70.91, 64.34, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (255, 51.18, 76.9, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (256, 66.63, 74.59, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (257, 59.83, 77.16, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (258, 66.11, 57.91, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (259, 64.34, 59.46, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (260, 94.56, 49.49, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (261, 68.43, 76.97, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (262, 59.72, 78.17, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (263, 63.73, 76.01, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (264, 54.52, 71.8, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (265, 55.45, 74.4, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (266, 86.17, 90.04, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (267, 64.55, 62.13, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (268, 81.52, 91.99, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (269, 79.25, 46.91, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (270, 65.3, 60.87, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (271, 90.37, 52.42, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (272, 68.53, 64.12, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (273, 58.99, 65.14, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (274, 83.55, 48.84, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (275, 91.43, 81.12, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (276, 90.8, 63.67, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (277, 93.89, 48.81, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (278, 59.29, 73.14, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (279, 89.23, 62.15, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (280, 84.02, 73.22, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (281, 68.7, 88.19, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (282, 58.12, 79.14, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (283, 81.49, 58.11, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (284, 51.56, 77.84, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (285, 64.56, 54.68, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (286, 66.78, 64.87, 'B');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (287, 89.93, 63.16, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (288, 54.55, 81.97, 'A');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (289, 65.75, 51.12, 'C+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (290, 70.98, 86.01, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (291, 80.13, 88.92, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (292, 77.28, 74.25, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (293, 90.04, 47.59, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (294, 85.38, 56.92, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (295, 88.79, 56.41, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (296, 74.28, 57.74, 'D');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (297, 53.96, 52.49, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (298, 89.97, 80.15, 'C');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (299, 68.34, 64.56, 'F');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (300, 80.53, 89.55, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (301, 73.4, 78.52, 'B+');
INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade) VALUES (302, 70.54, 64.94, 'B+');

-- 3.4 Fee payments (100 rows)
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026001', 4000, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026002', 5000, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026003', 4500, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026004', 4000, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026005', 4500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026006', 3500, '2026-05-26', 'Mobile Money', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026007', 4000, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026008', 5500, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026009', 5000, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026010', 5000, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026011', 5000, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026012', 5000, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026013', 5500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026014', 3500, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026015', 4000, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026016', 4000, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026017', 3500, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026018', 5000, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026019', 5000, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026020', 5000, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026021', 4500, '2026-05-26', 'Mobile Money', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026022', 4000, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026023', 3500, '2026-05-26', 'Mobile Money', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026024', 3500, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026025', 4000, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026026', 5000, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026027', 5000, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026028', 5500, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026029', 4000, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026030', 4500, '2026-05-26', 'Mobile Money', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026031', 5500, '2026-05-26', 'Mobile Money', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026032', 3500, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026033', 5000, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026034', 3500, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026035', 4500, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026036', 3500, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026037', 5000, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026038', 5500, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026039', 4500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026040', 3500, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026041', 3500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026042', 4500, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026043', 4000, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026044', 3500, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026045', 5000, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026046', 5500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026047', 3500, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026048', 5000, '2026-05-26', 'Mobile Money', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026049', 5000, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026050', 4000, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026051', 4500, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026052', 5000, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026053', 5000, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026054', 3500, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026055', 5000, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026056', 5500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026057', 4500, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026058', 5500, '2026-05-26', 'Mobile Money', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026059', 4000, '2026-05-26', 'Mobile Money', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026060', 5500, '2026-05-26', 'Mobile Money', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026061', 5500, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026062', 5500, '2026-05-26', 'Mobile Money', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026063', 4000, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026064', 5500, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026065', 5500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026066', 4500, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026067', 5500, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026068', 5500, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026069', 4500, '2026-05-26', 'Mobile Money', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026070', 5500, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026071', 5500, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026072', 3500, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026073', 3500, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026074', 5500, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026075', 5500, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026076', 5500, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026077', 3500, '2026-05-26', 'Card', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026078', 3500, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026079', 5000, '2026-05-26', 'Mobile Money', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026080', 4000, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026081', 5000, '2026-05-26', 'Bank', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026082', 5500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026083', 4000, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026084', 5000, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026085', 5000, '2026-05-26', 'Mobile Money', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026086', 5000, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026087', 4000, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026088', 4500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026089', 4000, '2026-05-26', 'Mobile Money', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026090', 4000, '2026-05-26', 'Card', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026091', 3500, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026092', 4500, '2026-05-26', 'Mobile Money', 1000);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026093', 5000, '2026-05-26', 'Bank', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026094', 5500, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026095', 5000, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026096', 3500, '2026-05-26', 'Mobile Money', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026097', 4500, '2026-05-26', 'Card', 0);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026098', 3500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026099', 5500, '2026-05-26', 'Bank', 500);
INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance) VALUES ('UG2026100', 5000, '2026-05-26', 'Mobile Money', 0);

-- 3.5 LMS activity (500 rows)
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026088', 1, '2026-05-27 10:18:46', 'Forum', 81);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026015', 2, '2026-05-27 10:16:35', 'Login', 24);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 4, '2026-05-27 10:16:03', 'PageView', 71);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026051', 1, '2026-05-27 10:18:19', 'Login', 48);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026079', 1, '2026-05-27 10:17:04', 'QuizAttempt', 75);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026015', 3, '2026-05-27 10:18:37', 'QuizAttempt', 48);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026023', 2, '2026-05-27 10:19:08', 'Login', 95);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026066', 1, '2026-05-27 10:17:06', 'PageView', 27);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026042', 5, '2026-05-27 10:17:34', 'PageView', 37);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026095', 5, '2026-05-27 10:14:38', 'PageView', 99);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026048', 3, '2026-05-27 10:18:06', 'Login', 88);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026015', 5, '2026-05-27 10:20:03', 'Forum', 100);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026045', 5, '2026-05-27 10:16:51', 'AssignmentUpload', 83);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026092', 5, '2026-05-27 10:19:11', 'Login', 90);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026087', 3, '2026-05-27 10:19:29', 'PageView', 18);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026029', 3, '2026-05-27 10:15:03', 'QuizAttempt', 29);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026041', 1, '2026-05-27 10:15:44', 'QuizAttempt', 18);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026069', 5, '2026-05-27 10:15:25', 'QuizAttempt', 52);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026079', 1, '2026-05-27 10:18:00', 'Forum', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026005', 4, '2026-05-27 10:16:11', 'PageView', 9);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026076', 4, '2026-05-27 10:17:45', 'AssignmentUpload', 17);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026007', 1, '2026-05-27 10:16:17', 'Login', 118);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026086', 4, '2026-05-27 10:15:32', 'PageView', 67);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 5, '2026-05-27 10:17:07', 'QuizAttempt', 118);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026082', 2, '2026-05-27 10:17:17', 'AssignmentUpload', 111);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026074', 1, '2026-05-27 10:19:27', 'PageView', 111);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026026', 1, '2026-05-27 10:15:08', 'PageView', 118);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026017', 3, '2026-05-27 10:15:03', 'QuizAttempt', 29);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026090', 1, '2026-05-27 10:18:33', 'PageView', 86);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 2, '2026-05-27 10:14:39', 'PageView', 97);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026095', 1, '2026-05-27 10:20:08', 'QuizAttempt', 94);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026021', 2, '2026-05-27 10:19:19', 'QuizAttempt', 78);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026009', 3, '2026-05-27 10:19:46', 'AssignmentUpload', 77);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026008', 1, '2026-05-27 10:19:10', 'QuizAttempt', 45);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026050', 5, '2026-05-27 10:20:01', 'Forum', 50);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026044', 2, '2026-05-27 10:18:18', 'Forum', 10);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026045', 1, '2026-05-27 10:17:41', 'AssignmentUpload', 112);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026004', 1, '2026-05-27 10:16:27', 'PageView', 60);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026007', 5, '2026-05-27 10:16:24', 'AssignmentUpload', 54);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026032', 4, '2026-05-27 10:17:05', 'Login', 38);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026083', 2, '2026-05-27 10:15:35', 'Login', 50);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026069', 4, '2026-05-27 10:18:38', 'QuizAttempt', 61);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026090', 4, '2026-05-27 10:16:32', 'AssignmentUpload', 60);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 4, '2026-05-27 10:16:05', 'Forum', 33);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026042', 5, '2026-05-27 10:17:55', 'Login', 98);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 5, '2026-05-27 10:14:19', 'AssignmentUpload', 103);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026093', 4, '2026-05-27 10:17:26', 'QuizAttempt', 23);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026083', 4, '2026-05-27 10:17:12', 'PageView', 99);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026014', 5, '2026-05-27 10:17:11', 'Login', 97);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026073', 3, '2026-05-27 10:17:37', 'Login', 6);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 2, '2026-05-27 10:16:32', 'QuizAttempt', 1);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026050', 5, '2026-05-27 10:18:06', 'Login', 117);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026014', 3, '2026-05-27 10:17:21', 'Forum', 21);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026003', 2, '2026-05-27 10:15:34', 'Login', 92);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026008', 1, '2026-05-27 10:14:36', 'PageView', 96);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026049', 1, '2026-05-27 10:18:45', 'AssignmentUpload', 105);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 4, '2026-05-27 10:18:09', 'AssignmentUpload', 12);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 4, '2026-05-27 10:15:44', 'PageView', 96);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026027', 5, '2026-05-27 10:15:16', 'QuizAttempt', 66);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026077', 1, '2026-05-27 10:14:37', 'PageView', 88);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 1, '2026-05-27 10:17:48', 'AssignmentUpload', 35);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026056', 4, '2026-05-27 10:14:21', 'Login', 89);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026025', 4, '2026-05-27 10:17:58', 'PageView', 46);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026085', 2, '2026-05-27 10:16:15', 'QuizAttempt', 80);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026003', 2, '2026-05-27 10:16:35', 'Login', 109);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026072', 1, '2026-05-27 10:17:57', 'QuizAttempt', 119);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026021', 5, '2026-05-27 10:18:07', 'PageView', 18);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 2, '2026-05-27 10:17:25', 'QuizAttempt', 62);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026098', 5, '2026-05-27 10:14:45', 'QuizAttempt', 10);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026044', 5, '2026-05-27 10:20:07', 'QuizAttempt', 44);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 1, '2026-05-27 10:17:33', 'AssignmentUpload', 7);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026039', 5, '2026-05-27 10:14:45', 'PageView', 115);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026076', 3, '2026-05-27 10:17:45', 'Login', 5);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026086', 5, '2026-05-27 10:16:10', 'Login', 70);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026035', 4, '2026-05-27 10:16:17', 'QuizAttempt', 113);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026094', 5, '2026-05-27 10:18:41', 'PageView', 27);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026048', 4, '2026-05-27 10:15:13', 'AssignmentUpload', 15);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026023', 5, '2026-05-27 10:14:27', 'PageView', 86);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026094', 2, '2026-05-27 10:14:26', 'Forum', 52);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026010', 5, '2026-05-27 10:15:12', 'QuizAttempt', 11);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026061', 1, '2026-05-27 10:19:01', 'Forum', 75);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026077', 4, '2026-05-27 10:17:03', 'Forum', 104);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026095', 5, '2026-05-27 10:16:47', 'QuizAttempt', 119);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026070', 4, '2026-05-27 10:15:01', 'Forum', 116);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026070', 4, '2026-05-27 10:19:47', 'Forum', 81);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 2, '2026-05-27 10:18:07', 'QuizAttempt', 15);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026066', 2, '2026-05-27 10:18:14', 'Login', 70);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026039', 3, '2026-05-27 10:16:14', 'Login', 1);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026053', 1, '2026-05-27 10:19:51', 'Login', 62);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026035', 5, '2026-05-27 10:16:02', 'Login', 80);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026069', 5, '2026-05-27 10:15:51', 'Forum', 11);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 2, '2026-05-27 10:17:50', 'PageView', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026040', 3, '2026-05-27 10:16:32', 'AssignmentUpload', 54);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026080', 5, '2026-05-27 10:18:38', 'AssignmentUpload', 81);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026024', 1, '2026-05-27 10:19:24', 'QuizAttempt', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 4, '2026-05-27 10:15:47', 'QuizAttempt', 41);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026100', 1, '2026-05-27 10:18:46', 'AssignmentUpload', 23);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026059', 4, '2026-05-27 10:16:26', 'Login', 78);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026002', 3, '2026-05-27 10:14:30', 'Forum', 31);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 4, '2026-05-27 10:15:39', 'QuizAttempt', 23);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026076', 3, '2026-05-27 10:15:33', 'AssignmentUpload', 19);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026019', 3, '2026-05-27 10:17:22', 'Login', 84);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026021', 3, '2026-05-27 10:17:22', 'AssignmentUpload', 12);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026042', 5, '2026-05-27 10:14:19', 'Login', 12);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026095', 3, '2026-05-27 10:16:40', 'PageView', 11);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026007', 3, '2026-05-27 10:14:54', 'PageView', 56);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026052', 2, '2026-05-27 10:16:23', 'Login', 111);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026020', 5, '2026-05-27 10:16:11', 'Forum', 2);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026050', 1, '2026-05-27 10:17:30', 'QuizAttempt', 95);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026040', 5, '2026-05-27 10:17:32', 'QuizAttempt', 96);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026049', 3, '2026-05-27 10:17:53', 'Forum', 12);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026013', 2, '2026-05-27 10:16:33', 'PageView', 28);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026054', 2, '2026-05-27 10:18:25', 'AssignmentUpload', 76);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026099', 1, '2026-05-27 10:15:33', 'QuizAttempt', 36);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026078', 5, '2026-05-27 10:15:23', 'AssignmentUpload', 20);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026094', 1, '2026-05-27 10:15:02', 'PageView', 34);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026028', 5, '2026-05-27 10:14:23', 'AssignmentUpload', 67);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 2, '2026-05-27 10:20:05', 'QuizAttempt', 33);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026030', 1, '2026-05-27 10:20:00', 'PageView', 56);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026088', 3, '2026-05-27 10:16:13', 'AssignmentUpload', 90);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026077', 1, '2026-05-27 10:18:46', 'AssignmentUpload', 74);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026056', 2, '2026-05-27 10:16:15', 'QuizAttempt', 75);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 5, '2026-05-27 10:17:01', 'PageView', 89);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 2, '2026-05-27 10:15:34', 'PageView', 41);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026045', 2, '2026-05-27 10:19:16', 'Login', 111);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026096', 5, '2026-05-27 10:17:23', 'PageView', 52);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026071', 4, '2026-05-27 10:17:42', 'PageView', 27);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026032', 2, '2026-05-27 10:19:52', 'Login', 8);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026032', 3, '2026-05-27 10:15:41', 'AssignmentUpload', 107);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026023', 1, '2026-05-27 10:19:43', 'Forum', 100);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026032', 4, '2026-05-27 10:15:57', 'AssignmentUpload', 48);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026028', 2, '2026-05-27 10:18:49', 'PageView', 95);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026008', 3, '2026-05-27 10:14:27', 'Forum', 18);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026028', 3, '2026-05-27 10:19:50', 'AssignmentUpload', 85);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026034', 1, '2026-05-27 10:16:45', 'QuizAttempt', 120);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026020', 4, '2026-05-27 10:17:45', 'PageView', 38);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026069', 2, '2026-05-27 10:18:26', 'AssignmentUpload', 4);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026079', 3, '2026-05-27 10:17:30', 'QuizAttempt', 96);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026095', 4, '2026-05-27 10:19:03', 'Forum', 113);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026014', 4, '2026-05-27 10:18:45', 'Login', 67);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026094', 1, '2026-05-27 10:18:04', 'Login', 34);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026099', 1, '2026-05-27 10:19:34', 'QuizAttempt', 48);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026005', 5, '2026-05-27 10:19:05', 'PageView', 59);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026026', 2, '2026-05-27 10:19:30', 'Login', 8);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026100', 4, '2026-05-27 10:18:22', 'Forum', 8);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026065', 4, '2026-05-27 10:15:42', 'QuizAttempt', 5);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026067', 2, '2026-05-27 10:16:49', 'QuizAttempt', 38);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 5, '2026-05-27 10:16:20', 'Forum', 100);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026082', 4, '2026-05-27 10:17:40', 'Login', 6);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026068', 2, '2026-05-27 10:17:16', 'PageView', 115);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 3, '2026-05-27 10:17:04', 'PageView', 45);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026050', 1, '2026-05-27 10:17:55', 'Forum', 37);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026015', 5, '2026-05-27 10:19:47', 'PageView', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 2, '2026-05-27 10:18:30', 'Forum', 55);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 4, '2026-05-27 10:19:54', 'QuizAttempt', 87);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026061', 3, '2026-05-27 10:16:53', 'QuizAttempt', 59);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026020', 4, '2026-05-27 10:19:37', 'Login', 10);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026096', 5, '2026-05-27 10:15:25', 'AssignmentUpload', 74);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026054', 4, '2026-05-27 10:18:11', 'PageView', 73);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 2, '2026-05-27 10:19:42', 'Forum', 114);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 5, '2026-05-27 10:19:07', 'Forum', 28);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026091', 3, '2026-05-27 10:16:00', 'Login', 43);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026096', 2, '2026-05-27 10:17:12', 'PageView', 77);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026017', 5, '2026-05-27 10:16:55', 'Login', 68);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026064', 5, '2026-05-27 10:15:14', 'AssignmentUpload', 99);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026070', 5, '2026-05-27 10:18:55', 'AssignmentUpload', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026040', 5, '2026-05-27 10:17:08', 'Forum', 16);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026070', 4, '2026-05-27 10:14:19', 'Login', 19);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026020', 3, '2026-05-27 10:19:03', 'PageView', 55);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026085', 3, '2026-05-27 10:18:50', 'PageView', 47);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026041', 5, '2026-05-27 10:19:38', 'QuizAttempt', 10);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026008', 2, '2026-05-27 10:19:31', 'AssignmentUpload', 96);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026005', 3, '2026-05-27 10:18:40', 'PageView', 17);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026033', 3, '2026-05-27 10:14:55', 'Forum', 61);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 3, '2026-05-27 10:15:26', 'QuizAttempt', 2);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026042', 3, '2026-05-27 10:19:03', 'Login', 106);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026004', 4, '2026-05-27 10:16:13', 'Forum', 106);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026029', 4, '2026-05-27 10:15:13', 'Login', 30);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026054', 2, '2026-05-27 10:14:17', 'AssignmentUpload', 79);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026069', 2, '2026-05-27 10:19:50', 'Login', 54);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026030', 2, '2026-05-27 10:17:41', 'PageView', 35);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026098', 4, '2026-05-27 10:15:39', 'Login', 7);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026081', 2, '2026-05-27 10:20:09', 'Login', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 4, '2026-05-27 10:16:33', 'Login', 85);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026039', 2, '2026-05-27 10:14:45', 'QuizAttempt', 23);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026006', 1, '2026-05-27 10:15:54', 'Login', 34);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 1, '2026-05-27 10:16:55', 'AssignmentUpload', 31);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026089', 2, '2026-05-27 10:15:00', 'QuizAttempt', 64);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 3, '2026-05-27 10:16:09', 'QuizAttempt', 52);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026059', 2, '2026-05-27 10:14:50', 'QuizAttempt', 119);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026001', 2, '2026-05-27 10:19:57', 'PageView', 73);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 5, '2026-05-27 10:14:46', 'Login', 88);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 4, '2026-05-27 10:14:14', 'PageView', 117);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026091', 2, '2026-05-27 10:15:08', 'PageView', 105);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026003', 5, '2026-05-27 10:14:38', 'PageView', 13);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026050', 1, '2026-05-27 10:19:59', 'AssignmentUpload', 69);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026088', 2, '2026-05-27 10:16:04', 'AssignmentUpload', 25);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 1, '2026-05-27 10:19:37', 'QuizAttempt', 3);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026085', 5, '2026-05-27 10:19:06', 'PageView', 74);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026006', 5, '2026-05-27 10:19:26', 'Forum', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026091', 1, '2026-05-27 10:18:15', 'AssignmentUpload', 107);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026009', 5, '2026-05-27 10:19:21', 'Login', 46);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026001', 4, '2026-05-27 10:14:19', 'Forum', 110);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026067', 4, '2026-05-27 10:14:54', 'Login', 5);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026026', 4, '2026-05-27 10:19:39', 'Forum', 36);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026086', 4, '2026-05-27 10:15:51', 'AssignmentUpload', 38);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026058', 1, '2026-05-27 10:19:55', 'QuizAttempt', 117);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026056', 4, '2026-05-27 10:18:15', 'PageView', 113);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 4, '2026-05-27 10:16:53', 'AssignmentUpload', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026083', 3, '2026-05-27 10:15:11', 'QuizAttempt', 22);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026025', 1, '2026-05-27 10:17:49', 'Login', 119);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026091', 3, '2026-05-27 10:18:11', 'AssignmentUpload', 18);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026008', 2, '2026-05-27 10:19:52', 'Forum', 43);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026068', 1, '2026-05-27 10:19:07', 'Login', 87);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026002', 4, '2026-05-27 10:19:29', 'PageView', 13);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026076', 1, '2026-05-27 10:15:00', 'QuizAttempt', 112);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026042', 5, '2026-05-27 10:18:19', 'Forum', 58);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026060', 5, '2026-05-27 10:15:29', 'PageView', 25);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026007', 1, '2026-05-27 10:15:52', 'PageView', 41);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026056', 1, '2026-05-27 10:18:45', 'Forum', 99);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026079', 3, '2026-05-27 10:15:15', 'AssignmentUpload', 99);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026079', 5, '2026-05-27 10:15:04', 'AssignmentUpload', 100);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026023', 1, '2026-05-27 10:18:52', 'Login', 43);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026089', 4, '2026-05-27 10:16:02', 'Forum', 36);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026012', 1, '2026-05-27 10:14:22', 'QuizAttempt', 17);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 4, '2026-05-27 10:17:06', 'PageView', 44);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026073', 1, '2026-05-27 10:15:47', 'Login', 43);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026054', 4, '2026-05-27 10:15:55', 'Forum', 27);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026039', 2, '2026-05-27 10:19:25', 'Login', 26);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026049', 4, '2026-05-27 10:17:12', 'PageView', 41);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026050', 1, '2026-05-27 10:15:11', 'AssignmentUpload', 48);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026061', 2, '2026-05-27 10:19:54', 'QuizAttempt', 77);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026056', 2, '2026-05-27 10:17:34', 'Login', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026023', 1, '2026-05-27 10:15:37', 'QuizAttempt', 9);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 2, '2026-05-27 10:14:53', 'Forum', 75);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026076', 4, '2026-05-27 10:18:34', 'Forum', 3);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 4, '2026-05-27 10:17:30', 'AssignmentUpload', 3);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026056', 2, '2026-05-27 10:14:56', 'AssignmentUpload', 65);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026069', 4, '2026-05-27 10:15:48', 'Login', 80);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 5, '2026-05-27 10:15:53', 'Login', 2);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026049', 1, '2026-05-27 10:16:49', 'QuizAttempt', 15);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026030', 5, '2026-05-27 10:15:23', 'PageView', 97);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026094', 4, '2026-05-27 10:15:33', 'Login', 71);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026089', 5, '2026-05-27 10:14:16', 'Login', 6);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026029', 1, '2026-05-27 10:19:15', 'Login', 29);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026044', 3, '2026-05-27 10:14:35', 'QuizAttempt', 44);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 2, '2026-05-27 10:19:04', 'Forum', 74);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026005', 5, '2026-05-27 10:20:06', 'Login', 23);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026041', 3, '2026-05-27 10:17:45', 'AssignmentUpload', 78);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026053', 5, '2026-05-27 10:17:39', 'PageView', 105);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026056', 5, '2026-05-27 10:17:57', 'Forum', 71);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026083', 5, '2026-05-27 10:18:41', 'AssignmentUpload', 112);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026008', 3, '2026-05-27 10:17:08', 'QuizAttempt', 66);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026071', 3, '2026-05-27 10:18:40', 'Login', 29);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026001', 5, '2026-05-27 10:18:17', 'Login', 10);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026100', 2, '2026-05-27 10:19:12', 'QuizAttempt', 29);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 1, '2026-05-27 10:18:50', 'Forum', 35);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026043', 1, '2026-05-27 10:19:36', 'Forum', 119);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 4, '2026-05-27 10:16:03', 'PageView', 21);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 1, '2026-05-27 10:20:02', 'Forum', 25);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026073', 5, '2026-05-27 10:16:59', 'AssignmentUpload', 9);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026021', 5, '2026-05-27 10:15:57', 'Login', 103);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026023', 3, '2026-05-27 10:16:31', 'PageView', 74);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026040', 2, '2026-05-27 10:14:53', 'PageView', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026095', 1, '2026-05-27 10:17:06', 'AssignmentUpload', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026037', 5, '2026-05-27 10:19:13', 'Forum', 104);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026089', 4, '2026-05-27 10:19:30', 'AssignmentUpload', 57);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026073', 1, '2026-05-27 10:18:02', 'Login', 1);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026077', 1, '2026-05-27 10:15:47', 'Login', 113);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026074', 4, '2026-05-27 10:16:02', 'PageView', 76);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026099', 1, '2026-05-27 10:17:02', 'QuizAttempt', 31);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026085', 2, '2026-05-27 10:19:05', 'Login', 79);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026055', 3, '2026-05-27 10:19:16', 'AssignmentUpload', 71);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026087', 2, '2026-05-27 10:18:55', 'PageView', 41);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026079', 2, '2026-05-27 10:14:18', 'PageView', 1);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026027', 1, '2026-05-27 10:18:47', 'PageView', 64);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026064', 4, '2026-05-27 10:19:18', 'QuizAttempt', 61);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026019', 4, '2026-05-27 10:15:15', 'PageView', 11);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026043', 5, '2026-05-27 10:19:04', 'Login', 55);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 1, '2026-05-27 10:18:28', 'Forum', 43);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026015', 3, '2026-05-27 10:17:16', 'PageView', 33);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026007', 1, '2026-05-27 10:15:40', 'Login', 71);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 4, '2026-05-27 10:15:31', 'QuizAttempt', 61);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026081', 1, '2026-05-27 10:17:32', 'QuizAttempt', 31);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026098', 3, '2026-05-27 10:19:16', 'Forum', 19);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026041', 2, '2026-05-27 10:19:00', 'Forum', 75);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 1, '2026-05-27 10:20:02', 'PageView', 106);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026093', 1, '2026-05-27 10:16:11', 'Login', 117);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026058', 5, '2026-05-27 10:15:23', 'AssignmentUpload', 74);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026085', 4, '2026-05-27 10:19:59', 'QuizAttempt', 4);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026074', 4, '2026-05-27 10:17:17', 'PageView', 46);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026093', 1, '2026-05-27 10:20:09', 'Login', 5);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026055', 3, '2026-05-27 10:16:55', 'QuizAttempt', 49);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026044', 4, '2026-05-27 10:16:39', 'QuizAttempt', 21);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 1, '2026-05-27 10:17:57', 'PageView', 34);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 1, '2026-05-27 10:19:48', 'PageView', 64);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026043', 5, '2026-05-27 10:15:37', 'PageView', 25);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026009', 5, '2026-05-27 10:18:37', 'AssignmentUpload', 117);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 2, '2026-05-27 10:15:54', 'Login', 11);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026045', 4, '2026-05-27 10:19:05', 'PageView', 29);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026073', 2, '2026-05-27 10:17:42', 'PageView', 40);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026049', 5, '2026-05-27 10:14:18', 'AssignmentUpload', 7);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026034', 5, '2026-05-27 10:18:29', 'Forum', 87);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026069', 3, '2026-05-27 10:17:57', 'QuizAttempt', 19);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026082', 5, '2026-05-27 10:18:47', 'Forum', 67);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 5, '2026-05-27 10:18:16', 'Forum', 32);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026096', 3, '2026-05-27 10:15:30', 'PageView', 23);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026001', 5, '2026-05-27 10:18:29', 'QuizAttempt', 55);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026091', 1, '2026-05-27 10:15:06', 'PageView', 119);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026026', 1, '2026-05-27 10:17:47', 'QuizAttempt', 31);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026062', 2, '2026-05-27 10:14:48', 'PageView', 70);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026001', 4, '2026-05-27 10:14:58', 'PageView', 8);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026026', 1, '2026-05-27 10:15:50', 'Forum', 4);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 3, '2026-05-27 10:19:34', 'QuizAttempt', 8);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026100', 2, '2026-05-27 10:15:53', 'PageView', 105);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026020', 1, '2026-05-27 10:19:45', 'AssignmentUpload', 14);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026092', 3, '2026-05-27 10:18:08', 'PageView', 36);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026056', 3, '2026-05-27 10:18:22', 'Login', 100);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026067', 3, '2026-05-27 10:15:05', 'Login', 107);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 1, '2026-05-27 10:14:48', 'Forum', 112);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026085', 2, '2026-05-27 10:14:47', 'AssignmentUpload', 49);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026031', 3, '2026-05-27 10:14:53', 'Login', 75);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 2, '2026-05-27 10:17:23', 'AssignmentUpload', 108);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026094', 4, '2026-05-27 10:17:24', 'QuizAttempt', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026045', 5, '2026-05-27 10:19:48', 'AssignmentUpload', 117);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026046', 5, '2026-05-27 10:18:25', 'Forum', 34);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026027', 1, '2026-05-27 10:15:16', 'Login', 30);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026086', 1, '2026-05-27 10:17:46', 'Login', 10);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026098', 1, '2026-05-27 10:16:19', 'Login', 116);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026074', 1, '2026-05-27 10:14:34', 'Forum', 38);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026050', 2, '2026-05-27 10:15:04', 'QuizAttempt', 5);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026043', 5, '2026-05-27 10:17:46', 'Forum', 14);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026016', 3, '2026-05-27 10:14:14', 'Forum', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026057', 1, '2026-05-27 10:19:30', 'Login', 62);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026030', 1, '2026-05-27 10:15:23', 'Forum', 37);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026009', 4, '2026-05-27 10:16:27', 'AssignmentUpload', 88);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026012', 5, '2026-05-27 10:19:28', 'Login', 50);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026076', 3, '2026-05-27 10:17:35', 'QuizAttempt', 49);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 2, '2026-05-27 10:19:05', 'QuizAttempt', 2);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026057', 4, '2026-05-27 10:19:31', 'QuizAttempt', 20);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026092', 1, '2026-05-27 10:15:02', 'Login', 74);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026002', 1, '2026-05-27 10:15:18', 'QuizAttempt', 26);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026092', 2, '2026-05-27 10:17:57', 'PageView', 107);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026080', 1, '2026-05-27 10:15:12', 'Login', 47);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026094', 3, '2026-05-27 10:14:56', 'QuizAttempt', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026014', 5, '2026-05-27 10:17:21', 'PageView', 10);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026059', 3, '2026-05-27 10:14:24', 'AssignmentUpload', 13);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026061', 1, '2026-05-27 10:17:57', 'AssignmentUpload', 63);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026005', 4, '2026-05-27 10:14:19', 'QuizAttempt', 15);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026053', 3, '2026-05-27 10:17:38', 'PageView', 83);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026030', 3, '2026-05-27 10:18:07', 'Login', 36);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026091', 5, '2026-05-27 10:16:55', 'Forum', 23);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026031', 4, '2026-05-27 10:15:18', 'AssignmentUpload', 43);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026040', 1, '2026-05-27 10:18:41', 'PageView', 75);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026025', 1, '2026-05-27 10:15:41', 'PageView', 93);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026054', 1, '2026-05-27 10:15:37', 'QuizAttempt', 116);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026097', 3, '2026-05-27 10:15:46', 'Login', 50);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 4, '2026-05-27 10:18:03', 'PageView', 19);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026038', 4, '2026-05-27 10:14:39', 'Login', 108);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026044', 2, '2026-05-27 10:14:29', 'Forum', 115);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026074', 3, '2026-05-27 10:17:57', 'Login', 111);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 5, '2026-05-27 10:18:52', 'PageView', 7);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026066', 1, '2026-05-27 10:18:33', 'AssignmentUpload', 55);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 4, '2026-05-27 10:18:36', 'Login', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026034', 1, '2026-05-27 10:16:41', 'QuizAttempt', 6);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026033', 2, '2026-05-27 10:19:19', 'QuizAttempt', 74);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026052', 2, '2026-05-27 10:15:27', 'AssignmentUpload', 12);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 5, '2026-05-27 10:16:55', 'Login', 57);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026073', 5, '2026-05-27 10:19:11', 'QuizAttempt', 60);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026073', 4, '2026-05-27 10:14:40', 'Login', 102);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026037', 5, '2026-05-27 10:18:40', 'Forum', 3);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026037', 3, '2026-05-27 10:17:51', 'QuizAttempt', 6);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026016', 2, '2026-05-27 10:18:39', 'AssignmentUpload', 47);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 1, '2026-05-27 10:17:59', 'PageView', 87);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026068', 3, '2026-05-27 10:17:01', 'AssignmentUpload', 93);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026049', 3, '2026-05-27 10:14:45', 'PageView', 14);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026088', 4, '2026-05-27 10:15:43', 'AssignmentUpload', 67);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026065', 2, '2026-05-27 10:19:28', 'Forum', 21);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026013', 5, '2026-05-27 10:16:34', 'PageView', 22);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026062', 5, '2026-05-27 10:15:29', 'PageView', 73);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026020', 2, '2026-05-27 10:14:41', 'AssignmentUpload', 27);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026073', 2, '2026-05-27 10:17:29', 'QuizAttempt', 32);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 2, '2026-05-27 10:18:25', 'Login', 83);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026065', 5, '2026-05-27 10:16:50', 'PageView', 63);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026086', 1, '2026-05-27 10:14:47', 'Forum', 96);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026079', 5, '2026-05-27 10:18:30', 'Login', 93);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026084', 5, '2026-05-27 10:17:14', 'PageView', 4);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026081', 5, '2026-05-27 10:19:51', 'AssignmentUpload', 63);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 5, '2026-05-27 10:18:17', 'AssignmentUpload', 83);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 3, '2026-05-27 10:18:04', 'Login', 1);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026017', 4, '2026-05-27 10:19:00', 'PageView', 25);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026033', 5, '2026-05-27 10:15:20', 'AssignmentUpload', 21);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026079', 4, '2026-05-27 10:17:25', 'Forum', 38);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026054', 4, '2026-05-27 10:14:56', 'QuizAttempt', 107);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026025', 4, '2026-05-27 10:17:16', 'QuizAttempt', 1);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026003', 1, '2026-05-27 10:15:22', 'Login', 15);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026059', 3, '2026-05-27 10:16:18', 'PageView', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026027', 4, '2026-05-27 10:18:35', 'Forum', 73);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026088', 4, '2026-05-27 10:18:43', 'QuizAttempt', 35);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026007', 1, '2026-05-27 10:14:50', 'Forum', 99);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026019', 3, '2026-05-27 10:17:45', 'Login', 68);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026014', 5, '2026-05-27 10:14:18', 'AssignmentUpload', 43);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026033', 1, '2026-05-27 10:16:18', 'Login', 17);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026080', 4, '2026-05-27 10:18:57', 'Forum', 118);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026029', 3, '2026-05-27 10:19:36', 'Forum', 9);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026029', 1, '2026-05-27 10:17:50', 'Forum', 9);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026086', 4, '2026-05-27 10:19:34', 'PageView', 94);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026081', 2, '2026-05-27 10:19:33', 'Login', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026040', 1, '2026-05-27 10:15:14', 'PageView', 19);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026057', 3, '2026-05-27 10:18:04', 'AssignmentUpload', 64);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026026', 4, '2026-05-27 10:19:52', 'PageView', 31);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026007', 2, '2026-05-27 10:16:49', 'PageView', 64);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026013', 3, '2026-05-27 10:19:00', 'AssignmentUpload', 8);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026040', 5, '2026-05-27 10:14:21', 'PageView', 61);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026074', 4, '2026-05-27 10:18:14', 'QuizAttempt', 53);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 3, '2026-05-27 10:16:06', 'Forum', 38);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026013', 5, '2026-05-27 10:15:01', 'QuizAttempt', 98);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026074', 1, '2026-05-27 10:16:17', 'AssignmentUpload', 89);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 2, '2026-05-27 10:17:15', 'Forum', 95);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 1, '2026-05-27 10:16:56', 'AssignmentUpload', 63);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026072', 2, '2026-05-27 10:17:37', 'Forum', 34);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026055', 2, '2026-05-27 10:19:20', 'AssignmentUpload', 37);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026057', 4, '2026-05-27 10:17:08', 'AssignmentUpload', 14);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026002', 4, '2026-05-27 10:19:26', 'PageView', 84);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026057', 5, '2026-05-27 10:14:17', 'AssignmentUpload', 115);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026003', 2, '2026-05-27 10:16:17', 'Login', 23);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026067', 3, '2026-05-27 10:19:26', 'AssignmentUpload', 114);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026018', 2, '2026-05-27 10:18:46', 'Forum', 55);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026070', 1, '2026-05-27 10:18:24', 'QuizAttempt', 105);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 1, '2026-05-27 10:16:30', 'PageView', 2);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026085', 4, '2026-05-27 10:18:58', 'AssignmentUpload', 65);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026032', 4, '2026-05-27 10:16:55', 'PageView', 51);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026083', 4, '2026-05-27 10:19:30', 'QuizAttempt', 81);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026048', 1, '2026-05-27 10:15:51', 'PageView', 7);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026078', 1, '2026-05-27 10:20:06', 'AssignmentUpload', 82);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026011', 5, '2026-05-27 10:18:43', 'Login', 86);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026064', 4, '2026-05-27 10:17:14', 'AssignmentUpload', 11);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026071', 3, '2026-05-27 10:19:44', 'AssignmentUpload', 81);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026058', 3, '2026-05-27 10:16:33', 'Forum', 87);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 5, '2026-05-27 10:19:09', 'QuizAttempt', 27);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026052', 5, '2026-05-27 10:14:44', 'Login', 84);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026033', 5, '2026-05-27 10:16:04', 'AssignmentUpload', 99);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026066', 4, '2026-05-27 10:15:29', 'AssignmentUpload', 96);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026089', 3, '2026-05-27 10:19:03', 'Login', 59);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026084', 5, '2026-05-27 10:17:55', 'Login', 75);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026071', 3, '2026-05-27 10:19:53', 'AssignmentUpload', 84);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026074', 1, '2026-05-27 10:15:35', 'Login', 27);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026006', 3, '2026-05-27 10:17:33', 'PageView', 82);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026053', 4, '2026-05-27 10:17:45', 'QuizAttempt', 72);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026022', 2, '2026-05-27 10:17:49', 'AssignmentUpload', 58);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026017', 4, '2026-05-27 10:16:52', 'Login', 20);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026075', 1, '2026-05-27 10:15:55', 'QuizAttempt', 112);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026010', 2, '2026-05-27 10:14:19', 'AssignmentUpload', 36);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026032', 4, '2026-05-27 10:19:32', 'AssignmentUpload', 35);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026083', 4, '2026-05-27 10:19:24', 'QuizAttempt', 52);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026064', 3, '2026-05-27 10:14:45', 'Login', 81);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026082', 5, '2026-05-27 10:18:55', 'Forum', 116);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026070', 1, '2026-05-27 10:16:34', 'PageView', 37);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026089', 4, '2026-05-27 10:19:06', 'AssignmentUpload', 93);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026021', 4, '2026-05-27 10:18:29', 'Forum', 17);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026010', 2, '2026-05-27 10:19:04', 'AssignmentUpload', 104);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026077', 3, '2026-05-27 10:19:18', 'AssignmentUpload', 58);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026049', 5, '2026-05-27 10:18:39', 'Forum', 85);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026077', 4, '2026-05-27 10:16:44', 'AssignmentUpload', 78);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026025', 1, '2026-05-27 10:14:43', 'Forum', 66);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026070', 1, '2026-05-27 10:15:47', 'Login', 49);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026086', 4, '2026-05-27 10:18:59', 'PageView', 83);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026065', 5, '2026-05-27 10:16:24', 'PageView', 95);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026026', 1, '2026-05-27 10:14:17', 'AssignmentUpload', 54);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026020', 4, '2026-05-27 10:15:52', 'PageView', 102);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026011', 1, '2026-05-27 10:15:15', 'PageView', 95);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026047', 3, '2026-05-27 10:17:10', 'Login', 95);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026081', 3, '2026-05-27 10:18:01', 'QuizAttempt', 106);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026096', 2, '2026-05-27 10:17:35', 'AssignmentUpload', 57);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026015', 5, '2026-05-27 10:14:53', 'AssignmentUpload', 20);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026016', 3, '2026-05-27 10:18:43', 'Forum', 78);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026009', 4, '2026-05-27 10:15:35', 'PageView', 98);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026067', 1, '2026-05-27 10:17:37', 'QuizAttempt', 83);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026036', 1, '2026-05-27 10:17:55', 'PageView', 102);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026010', 5, '2026-05-27 10:15:27', 'PageView', 26);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 1, '2026-05-27 10:16:21', 'QuizAttempt', 40);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026015', 2, '2026-05-27 10:18:50', 'AssignmentUpload', 49);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026071', 3, '2026-05-27 10:19:44', 'AssignmentUpload', 32);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026033', 4, '2026-05-27 10:14:26', 'QuizAttempt', 113);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026051', 3, '2026-05-27 10:19:59', 'Login', 1);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026013', 1, '2026-05-27 10:15:20', 'Forum', 31);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026011', 1, '2026-05-27 10:18:22', 'Forum', 100);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026003', 2, '2026-05-27 10:19:16', 'AssignmentUpload', 45);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026061', 2, '2026-05-27 10:14:16', 'Login', 13);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026025', 3, '2026-05-27 10:15:46', 'Forum', 107);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026033', 2, '2026-05-27 10:15:34', 'Login', 36);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026064', 5, '2026-05-27 10:17:05', 'QuizAttempt', 5);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026068', 3, '2026-05-27 10:14:33', 'Login', 64);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026077', 3, '2026-05-27 10:15:17', 'QuizAttempt', 95);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026092', 3, '2026-05-27 10:20:09', 'QuizAttempt', 76);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026063', 2, '2026-05-27 10:18:03', 'Forum', 104);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026071', 4, '2026-05-27 10:15:35', 'QuizAttempt', 94);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026034', 2, '2026-05-27 10:14:30', 'Login', 100);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026052', 3, '2026-05-27 10:19:29', 'PageView', 93);
INSERT INTO LMSActivity (StudentID, CourseOfferingID, LoginTimestamp, ActivityType, DurationMinutes) VALUES ('UG2026001', 3, '2026-05-27 10:19:31', 'Forum', 13);

-- =====================================================================
-- 4. OPERATIONAL INDEXES
-- =====================================================================
CREATE INDEX idx_enrollment_student  ON Enrollment(StudentID);
CREATE INDEX idx_enrollment_offering ON Enrollment(CourseOfferingID);
CREATE INDEX idx_lms_student_off     ON LMSActivity(StudentID, CourseOfferingID);
CREATE INDEX idx_fee_student         ON FeePayment(StudentID);
CREATE INDEX idx_offering_sem_year   ON CourseOffering(SemesterID, AcademicYear);

-- =====================================================================
-- 5. GRADING / REPORTING VIEW
--    Weighted mark = 40% coursework + 60% exam (institutional policy).
-- =====================================================================
CREATE VIEW v_student_grade_summary AS
SELECT  e.EnrollmentID,
        s.StudentID,
        s.FirstName || ' ' || s.LastName AS FullName,
        p.ProgrammeName,
        c.CourseCode,
        c.CourseTitle,
        ar.CourseworkScore,
        ar.ExamScore,
        ROUND(0.40 * ar.CourseworkScore + 0.60 * ar.ExamScore, 2) AS WeightedMark,
        ar.FinalGrade
FROM        Enrollment       e
JOIN        Student          s  ON s.StudentID        = e.StudentID
JOIN        Programme        p  ON p.ProgrammeID      = s.ProgrammeID
JOIN        CourseOffering   co ON co.CourseOfferingID= e.CourseOfferingID
JOIN        Course           c  ON c.CourseID         = co.CourseID
LEFT JOIN   AssessmentResult ar ON ar.EnrollmentID    = e.EnrollmentID;

-- =====================================================================
-- 6. INTEGRITY VERIFICATION  (should all return 0 problem rows)
-- =====================================================================
-- 6.1 Row-count summary
SELECT 'Department'     AS table_name, COUNT(*) FROM Department
UNION ALL SELECT 'Programme',        COUNT(*) FROM Programme
UNION ALL SELECT 'Course',           COUNT(*) FROM Course
UNION ALL SELECT 'Lecturer',         COUNT(*) FROM Lecturer
UNION ALL SELECT 'Semester',         COUNT(*) FROM Semester
UNION ALL SELECT 'CourseOffering',   COUNT(*) FROM CourseOffering
UNION ALL SELECT 'Student',          COUNT(*) FROM Student
UNION ALL SELECT 'Enrollment',       COUNT(*) FROM Enrollment
UNION ALL SELECT 'AssessmentResult', COUNT(*) FROM AssessmentResult
UNION ALL SELECT 'FeePayment',       COUNT(*) FROM FeePayment
UNION ALL SELECT 'LMSActivity',      COUNT(*) FROM LMSActivity;

-- 6.2 Orphan checks (each must be empty)
SELECT * FROM Enrollment e LEFT JOIN Student s ON e.StudentID = s.StudentID WHERE s.StudentID IS NULL;
SELECT * FROM AssessmentResult a LEFT JOIN Enrollment e ON a.EnrollmentID = e.EnrollmentID WHERE e.EnrollmentID IS NULL;

-- =====================================================================
-- 7. INSTITUTIONAL ANALYTICS
-- =====================================================================

-- Q1: Enrolment load + credit hours per student
SELECT s.StudentID,
       s.FirstName || ' ' || s.LastName AS FullName,
       p.ProgrammeName,
       COUNT(e.EnrollmentID) AS CoursesTaken,
       SUM(c.CreditHours)    AS TotalCreditHours
FROM   Student s
JOIN   Programme p       ON s.ProgrammeID = p.ProgrammeID
JOIN   Enrollment e      ON s.StudentID = e.StudentID
JOIN   CourseOffering co ON e.CourseOfferingID = co.CourseOfferingID
JOIN   Course c          ON co.CourseID = c.CourseID
GROUP  BY s.StudentID, s.FirstName, s.LastName, p.ProgrammeName
ORDER  BY TotalCreditHours DESC, s.StudentID
LIMIT 100;

-- Q2: Programme-level performance (weighted mark + grade distribution)
SELECT p.ProgrammeName,
       COUNT(*)                                              AS Results,
       ROUND(AVG(0.40*ar.CourseworkScore + 0.60*ar.ExamScore),2) AS AvgWeightedMark,
       SUM(CASE WHEN ar.FinalGrade = 'A'  THEN 1 ELSE 0 END) AS Grade_A,
       SUM(CASE WHEN ar.FinalGrade = 'F'  THEN 1 ELSE 0 END) AS Grade_F
FROM   Programme p
JOIN   Student s           ON p.ProgrammeID = s.ProgrammeID
JOIN   Enrollment e        ON s.StudentID = e.StudentID
JOIN   AssessmentResult ar ON ar.EnrollmentID = e.EnrollmentID
GROUP  BY p.ProgrammeName
ORDER  BY AvgWeightedMark DESC;

-- Q3: LMS engagement vs outcome (early-warning / retention signal)
SELECT s.StudentID,
       co.CourseOfferingID,
       COUNT(l.ActivityID)            AS LMSEvents,
       COALESCE(SUM(l.DurationMinutes),0) AS TotalMinutes,
       ar.FinalGrade
FROM   Student s
JOIN   Enrollment e        ON s.StudentID = e.StudentID
JOIN   CourseOffering co   ON e.CourseOfferingID = co.CourseOfferingID
LEFT JOIN LMSActivity l    ON l.StudentID = s.StudentID
                          AND l.CourseOfferingID = co.CourseOfferingID
LEFT JOIN AssessmentResult ar ON ar.EnrollmentID = e.EnrollmentID
GROUP  BY s.StudentID, co.CourseOfferingID, ar.FinalGrade
ORDER  BY TotalMinutes DESC NULLS LAST
LIMIT 100;

-- Q4: Outstanding fee balances (financial governance)
SELECT s.StudentID, s.FirstName || ' ' || s.LastName AS FullName,
       SUM(f.AmountPaid) AS TotalPaid, SUM(f.Balance) AS OutstandingBalance
FROM   Student s JOIN FeePayment f ON s.StudentID = f.StudentID
GROUP  BY s.StudentID, s.FirstName, s.LastName
HAVING SUM(f.Balance) > 0
ORDER  BY OutstandingBalance DESC
LIMIT 100;

-- END OF SCRIPT


SELECT * FROM Student;

SELECT * FROM Lecturer;

SELECT * FROM course;

SELECT * FROM Department;

SELECT 
    s.studentid,
    s.firstname,lastname,
    p.programmename
FROM Student s
JOIN Programme p
ON s.programmeid = p.programmeid;

SELECT 
    StudentID,
    SUM(AmountPaid) AS TotalPaid,
    MAX(Balance) AS OutstandingBalance
FROM FeePayment
GROUP BY StudentID
HAVING MAX(Balance) > 0;

SELECT 
    SUM(AmountPaid) AS TotalRevenue
FROM FeePayment;

SELECT 
    p.ProgrammeName,
    COUNT(s.StudentID) AS TotalStudents
FROM Student s
JOIN Programme p
ON s.ProgrammeID = p.ProgrammeID
GROUP BY p.ProgrammeName;

SELECT
    s.firstName,
    lastname,
    c.CourseID,CourseTitle

FROM Enrollment e

JOIN Student s
ON e.StudentID = s.StudentID

JOIN CourseOffering co
ON e.CourseOfferingID = co.CourseOfferingID

JOIN Course c
ON co.CourseID = c.CourseID;

SELECT * FROM Course;

SELECT 
    PaymentMethod,
    COUNT(*) AS TotalTransactions,
    SUM(AmountPaid) AS TotalAmount
FROM FeePayment
GROUP BY PaymentMethod;

SELECT 
    c.CourseTitle,
    COUNT(e.EnrollmentID) AS TotalEnrollments
FROM Enrollment e
JOIN CourseOffering co
ON e.CourseOfferingID = co.CourseOfferingID
JOIN Course c
ON co.CourseID = c.CourseID
GROUP BY c.CourseTitle
ORDER BY TotalEnrollments DESC;


