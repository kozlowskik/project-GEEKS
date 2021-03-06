--createTables.sql - GradeBook

--Zaid Bhujwala, Zach Boylan, Steven Rollo, Sean Murthy
--Data Science & Systems Lab (DASSL), Western Connecticut State University (WCSU)

--(C) 2017- DASSL. ALL RIGHTS RESERVED.
--Licensed to others under CC 4.0 BY-SA-NC
--https://creativecommons.org/licenses/by-nc-sa/4.0/

--PROVIDED AS IS. NO WARRANTIES EXPRESSED OR IMPLIED. USE AT YOUR OWN RISK.

--This script creates schema, tables, and indexes for the Gradebook application

--E-mail address management is based on the discussion presented at:
-- https://gist.github.com/smurthys/feba310d8cc89c4e05bdb797ca0c6cac

--This script should be run after running the script initializeDB.sql
-- in the normal course of operations, this script should not be run
-- individually, but instead should be called from the script prepareDB.sql

--This script assumes a schema named "Gradebook" already exists and is empty

---------------------------------------------------------------------------------------
-- Original content updated by Team GEEKS
-- Bruno DaSilva, Cristian Fitzgerald, Eliot Griffin, Kenneth Kozlowski 


CREATE TABLE Gradebook.Course
(
   Number VARCHAR(11) NOT NULL, --e.g., 'CS170'
   Title VARCHAR(100) NOT NULL, --e.g., 'C++ Programming'
   Credits INT NOT NULL, --e.g., '4'
   PRIMARY KEY (Number,Title)
);


CREATE TABLE Gradebook.Season
(
   --Order denotes the sequence of seasons within a year: 0, 1,...9
   "Order" NUMERIC(1,0) PRIMARY KEY CHECK ("Order" >= 0),

   --Name is a description such as Spring and Summer: must be 2 or more chars
   -- uniqueness is enforced using a case-insensitive index
   Name VARCHAR(20) NOT NULL CHECK(LENGTH(TRIM(Name)) > 1),

   --Code is 'S', 'M', etc.: makes it easier for user to specify a season
   -- permit only A-Z (upper case)
   Code CHAR(1) NOT NULL UNIQUE CHECK(Code ~ '[A-Z]')
);

--enforce case-insensitive uniqueness of season name
CREATE UNIQUE INDEX idx_Unique_SeasonName ON Gradebook.Season(LOWER(TRIM(Name)));


CREATE TABLE Gradebook.Term
(
   ID SERIAL NOT NULL PRIMARY KEY,
   Year NUMERIC(4,0) NOT NULL CHECK (Year > 0), --'2017'
   Season NUMERIC(1,0) NOT NULL REFERENCES Gradebook.Season,
   StartDate DATE NOT NULL, --date the term begins
   EndDate DATE NOT NULL, --date the term ends (last day of  "finals" week)
   UNIQUE(Year, Season)
);


CREATE TABLE Gradebook.Instructor
(
   ID SERIAL PRIMARY KEY,
   FName VARCHAR(50) NOT NULL,
   MName VARCHAR(50),
   LName VARCHAR(50) NOT NULL,
   Department VARCHAR(30),
   Email VARCHAR(319) CHECK(TRIM(Email) LIKE '_%@_%._%'),
   UNIQUE(FName, MName, LName)
);

--enforce case-insensitive uniqueness of instructor e-mail addresses
CREATE UNIQUE INDEX idx_Unique_InstructorEmail
ON Gradebook.Instructor(LOWER(TRIM(Email)));

--Create a partial index on the instructor names.  This enforces the CONSTRAINT
-- that only one of any (FName, NULL, LName) is unique
CREATE UNIQUE INDEX idx_Unique_Names_NULL
ON Gradebook.Instructor(FName, LName)
WHERE MName IS NULL;

CREATE TABLE Gradebook.Section
(
   ID SERIAL PRIMARY KEY,
   Term INT NOT NULL REFERENCES Gradebook.Term,
   Course VARCHAR(11) NOT NULL,
   SectionNumber VARCHAR(3) NOT NULL, --'01', '72', etc.
   CRN VARCHAR(5) NOT NULL, --store this info for the registrar's benefit?
   Schedule VARCHAR(7),  --days the class meets: 'MW', 'TR', 'MWF', etc.
   Capacity INT, -- capacity of the class
   Location VARCHAR(25), --likely a classroom
   StartDate DATE, --first date the section meets
   EndDate DATE, --last date the section meets
   MidtermDate DATE, --date of the "middle" of term: used to compute mid-term grade
   Instructor1 INT NOT NULL REFERENCES Gradebook.Instructor, --primary instructor
   Instructor2 INT REFERENCES Gradebook.Instructor, --optional 2nd instructor
   Instructor3 INT REFERENCES Gradebook.Instructor, --optional 3rd instructor
   UNIQUE(Term, Course, SectionNumber, CRN),
   --make sure instructors are distinct
   CONSTRAINT DistinctSectionInstructors
        CHECK (Instructor1 <> Instructor2
               AND Instructor1 <> Instructor3
               AND Instructor2 <> Instructor3
              )
);


--Table to store all possible letter grades
--some universities permit A+
CREATE TABLE Gradebook.Grade
(
   Letter VARCHAR(2) NOT NULL PRIMARY KEY,
   GPA NUMERIC(4,3) UNIQUE,
   CONSTRAINT LetterChoices
      CHECK (Letter IN ('A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+',
                        'C', 'C-', 'D+', 'D', 'D-', 'F', 'W')
            ),
   CONSTRAINT GPAChoices
      CHECK (GPA IN (4.333, 4, 3.667, 3.333, 3, 2.667, 2.333, 2, 1.667, 1.333, 1, 0.667, 0)),
   UNIQUE(Letter,GPA) --Combinations of letter grade and GPA must be unique
);


--Table to store mapping of percentage score to a letter grade: varies by section
CREATE TABLE Gradebook.Section_GradeTier
(
   Section INT REFERENCES Gradebook.Section,
   LetterGrade VARCHAR(2) NOT NULL REFERENCES Gradebook.Grade,
   LowPercentage NUMERIC(5,2) NOT NULL CHECK (LowPercentage >= 0),
   HighPercentage NUMERIC(5,2) NOT NULL CHECK (HighPercentage >= 0),
   PRIMARY KEY(Section, LetterGrade),
   UNIQUE(Section, LowPercentage, HighPercentage)
);


CREATE TABLE Gradebook.Student
(
   ID SERIAL PRIMARY KEY,
   FName VARCHAR(50), --at least one of the name fields must be used: see below
   MName VARCHAR(50), --permit NULL in all 3 fields because some people have only one name: not sure which field will be used
   LName VARCHAR(50), --use a CONSTRAINT on names instead of NOT NULL until we understand the data
   SchoolIssuedID VARCHAR(50) NOT NULL UNIQUE,
   Email VARCHAR(319) CHECK(TRIM(Email) LIKE '_%@_%._%'),
   Major VARCHAR(50), --non-matriculated students are not required to have a major
   Year VARCHAR(30), --represents the student year. Ex: Freshman, Sophomore, Junior, Senior
   CONSTRAINT StudentNameRequired --ensure at least one of the name fields is used
      CHECK (FName IS NOT NULL OR MName IS NOT NULL OR LName IS NOT NULL)
);

--enforce case-insensitive uniqueness of student e-mail addresses
CREATE UNIQUE INDEX idx_Unique_StudentEmail
ON Gradebook.Student(LOWER(TRIM(Email)));


CREATE TABLE Gradebook.Enrollee
(
   Student INT NOT NULL REFERENCES Gradebook.Student,
   Section INT REFERENCES Gradebook.Section,
   DateEnrolled DATE NULL, --used to figure out which assessment components to include/exclude
   YearEnrolled VARCHAR(30) NOT NULL,
   MajorEnrolled VARCHAR(50) NOT NULL,
   MidtermWeightedAggregate NUMERIC(5,2), --weighted aggregate computed at mid-term
   MidtermGradeComputed VARCHAR(2), --will eventually move to a view
   MidtermGradeAwarded VARCHAR(2), --actual grade assigned, if any
   FinalWeightedAggregate NUMERIC(5,2), --weighted aggregate computed at end
   FinalGradeComputed VARCHAR(2),  --will eventually move to a view
   FinalGradeAwarded VARCHAR(2), --actual grade assigned
   PRIMARY KEY (Student, Section),
   FOREIGN KEY (Section, MidtermGradeAwarded) REFERENCES Gradebook.Section_GradeTier,
   FOREIGN KEY (Section, FinalGradeAwarded) REFERENCES Gradebook.Section_GradeTier
);


CREATE TABLE Gradebook.AttendanceStatus
(
   Status CHAR(1) NOT NULL PRIMARY KEY, --'P', 'A', ...
   Description VARCHAR(20) NOT NULL UNIQUE --'Present', 'Absent', ...
);


CREATE TABLE Gradebook.AttendanceRecord
(
   Student INT NOT NULL,
   Section INT NOT NULL,
   Date DATE NOT NULL,
   Status CHAR(1) NOT NULL REFERENCES Gradebook.AttendanceStatus,
   PRIMARY KEY (Student, Section, Date),
   FOREIGN KEY (Student, Section) REFERENCES Gradebook.Enrollee
);


CREATE TABLE Gradebook.Section_AssessmentKind
(
   Section INT NOT NULL REFERENCES Gradebook.Section,
   Name VARCHAR(20) NOT NULL CHECK(TRIM(Name) <> ''), --"Assignment", "Quiz", "Exam",...
   Description VARCHAR(100),
   Weightage NUMERIC(3,2) NOT NULL CHECK (Weightage >= 0), --a percentage value: 0.25, 0.5,...
   PRIMARY KEY (Section, Name)
);


CREATE TABLE Gradebook.Section_AssessmentItem
(
   Section INT NOT NULL REFERENCES Gradebook.Section,
   Kind VARCHAR(20) NOT NULL,
   AssessmentNumber INT NOT NULL CHECK (AssessmentNumber > 0),
   Description VARCHAR(100),
   BasePointsPossible NUMERIC(5,2) NOT NULL CHECK (BasePointsPossible >= 0),
   AssignedDate DATE NOT NULL,
   DueDate DATE NOT NULL,
   RevealDate DATE,
   Curve NUMERIC(3,2) DEFAULT 1.00, --A curve for the item
   PRIMARY KEY(Section, Kind, AssessmentNumber),
   FOREIGN KEY (Section, Kind) REFERENCES Gradebook.Section_AssessmentKind
);


CREATE TABLE Gradebook.Submission
(
   Student INT NOT NULL,
   Section INT NOT NULL,
   Kind VARCHAR(20) NOT NULL,
   AssessmentNumber INT NOT NULL,
   BasePointsEarned NUMERIC(5,2) CHECK (BasePointsEarned >= 0),
   ExtraCreditEarned NUMERIC(5,2) DEFAULT 1.00 CHECK (ExtraCreditEarned >= 0),
   Penalty NUMERIC(5,2) DEFAULT 1.00 CHECK (Penalty >= 0),
   CurvedGradeLetter VARCHAR(2),-- NUMERIC(5,2) NOT NULL,
   CurvedGradePercent NUMERIC(5,2),
   SubmissionDate DATE,   
   Notes VARCHAR(50), --Optional notes about the submission
   PRIMARY KEY(Student, Section, Kind, AssessmentNumber),
   FOREIGN KEY (Student, Section) REFERENCES Gradebook.Enrollee,
   FOREIGN KEY (Section, Kind, AssessmentNumber) REFERENCES Gradebook.Section_AssessmentItem
);
