# MediCommand AI — AI-Powered Hospital Command Center

An intelligent hospital operations dashboard designed to help hospital staff monitor patient admissions, bed availability, nurse assignments, triage priorities, critical alerts, and occupancy forecasts through a centralized interface.

**GitHub Repository:** https://github.com/Asma-039/medicommand-ai

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Problem Statement](#problem-statement)
3. [Objectives](#objectives)
4. [Key Features](#key-features)
5. [Technology Stack](#technology-stack)
6. [System Architecture](#system-architecture)
7. [Database Design](#database-design)
8. [Triage and Forecasting](#triage-and-forecasting)
9. [Project Structure](#project-structure)
10. [Installation and Setup](#installation-and-setup)
11. [Running the Application](#running-the-application)
12. [Security Considerations](#security-considerations)
13. [Future Enhancements](#future-enhancements)
14. [Team Members](#team-members)
15. [Repository](#repository)

---

## Project Overview

Hospitals manage large amounts of operational information, including patient admissions, ward capacity, bed availability, staff assignments, and emergency cases. When this information is scattered across different systems or handled manually, it can become difficult to coordinate resources efficiently.

MediCommand AI provides a centralized hospital command center that presents important operational information in one dashboard. It combines a web-based interface with a PostgreSQL database hosted on Supabase to support hospital resource monitoring, patient prioritization, and occupancy planning.

The project demonstrates the application of database management concepts, full-stack web development, and rule-based decision support in a healthcare operations scenario.

## Problem Statement

Hospital administrators and healthcare staff need a reliable way to monitor patient admissions, bed occupancy, nurse availability, and critical cases. Manual coordination can delay decisions, reduce visibility into available resources, and make it difficult to anticipate capacity problems.

The objective of MediCommand AI is to develop a centralized system that organizes hospital operational data, assists with patient triage prioritization, and presents occupancy forecasts to support better resource planning.

## Objectives

- Develop a centralized hospital operations dashboard.
- Monitor rooms, wards, beds, patients, and nurse assignments.
- Organize patients according to triage severity and priority.
- Assist with initial triage classification using patient information.
- Display critical alerts and important operational information.
- Generate a three-day hospital occupancy forecast.
- Apply database concepts such as relational tables, views, constraints, and database-side logic where implemented.
- Provide a clear and maintainable interface for hospital operations.

## Key Features

### 1. Overview Dashboard
Provides a centralized view of hospital operations and important status information.

### 2. Rooms and Beds Management
Displays room and bed information to help staff monitor capacity and bed availability.

### 3. Patient Management
Displays admitted patients and organizes the priority queue by severity, triage score, and waiting time.

### 4. Patient Triage
Uses patient-provided symptoms and vital signs to generate a triage preview, including severity and suggested department or doctor, according to the implemented triage rules.

### 5. Nurse Assignments
Supports nurse assignment based on availability and ward information, according to the configured application logic.

### 6. Critical Alerts
Provides a dedicated interface for reviewing important hospital alerts.

### 7. AI-Assisted Occupancy Forecast
Presents a three-day occupancy forecast for the hospital and individual wards, with a recalculation option.

**Important:** Triage recommendations and occupancy forecasts are decision-support features. They do not replace professional medical judgment or hospital policies.

## Technology Stack

| Component | Technology |
|---|---|
| Frontend | React |
| Programming language | TypeScript |
| Build tool and development server | Vite |
| Styling | CSS and project styling configuration |
| Database | PostgreSQL |
| Database hosting and integration | Supabase |
| Database query interface | Supabase JavaScript client |
| Version control | Git |
| Source code hosting | GitHub |

## System Architecture

The application follows a web-based architecture:

1. **Presentation layer:** React and TypeScript render the hospital dashboard and user interactions.
2. **Application layer:** Application components implement the interface logic and communicate with the database.
3. **Database layer:** PostgreSQL stores hospital data and provides the database structures and queries used by the application.
4. **Cloud database service:** Supabase provides database connectivity and related configuration.

The exact data flow depends on the implemented components and database configuration.

## Database Design

The database is designed to organize hospital operational information using relational data structures.

The project database and documentation may include structures for:

- Patients and admissions
- Doctors and nurses
- Wards, rooms, and beds
- Triage assessments and priority queues
- Nurse assignments and staff shifts
- Critical alerts
- Hospital occupancy forecasts

Database scripts and supporting documentation are maintained in the `database/` and `docs/` directories.

The database implementation uses the SQL scripts provided with the project. Refer to those scripts and the database documentation for the exact tables, relationships, constraints, views, functions, procedures, and triggers implemented.

## Triage and Forecasting

### Triage Prioritization

The triage feature uses patient information such as symptoms and vital signs to calculate a priority classification according to the implemented rules. Patients are organized by severity and other queue criteria to help staff identify cases requiring attention.

This feature is intended for academic demonstration and decision support, not as a substitute for a validated clinical triage system.

### Occupancy Forecasting

The forecasting feature presents estimated occupancy for the upcoming three days at hospital and ward levels. Forecasts are intended to support capacity planning and resource awareness.

The forecast method should be understood from the corresponding implementation and database scripts; the project should not be interpreted as using a trained machine-learning model unless such a model is actually implemented.

## Project Structure

```text
medicommand-ai/
├── src/                 # React and TypeScript application
│   └── lib/             # Shared application utilities
├── database/            # SQL scripts and database setup
├── docs/                # Project documentation and diagrams
├── public/              # Static public assets, if present
├── .env.example         # Example environment configuration
├── .gitignore           # Files excluded from version control
├── index.html           # Application entry HTML
├── package.json         # Dependencies and project scripts
├── package-lock.json    # Locked dependency versions
├── tsconfig.json        # TypeScript configuration
└── vite.config.ts       # Vite configuration
```

This structure describes the main project directories; optional files may vary depending on the current project version.

## Installation and Setup

### Prerequisites

Install the following before running the application:

- [Node.js](https://nodejs.org/) with npm
- [Git](https://git-scm.com/) (optional for cloning and version control)
- A Supabase project with the required database schema and SQL scripts configured

### Step 1: Clone the Repository

```bash
git clone https://github.com/Asma-039/medicommand-ai.git
cd medicommand-ai
```

### Step 2: Install Dependencies

```bash
npm install
```

### Step 3: Configure Supabase

Create a local environment file based on `.env.example`, if provided:

```text
VITE_SUPABASE_URL=your_supabase_project_url
VITE_SUPABASE_ANON_KEY=your_supabase_publishable_or_anon_key
```

Use the exact environment variable names expected by the application code. The names above are examples and must be checked against the project's Supabase client configuration.

Replace the placeholder values with the appropriate values from your own Supabase project.

### Step 4: Set Up the Database

1. Open your Supabase project.
2. Open the SQL Editor.
3. Review the SQL scripts available in the repository's `database/` directory.
4. Execute the scripts in their documented dependency order.
5. Verify that the required tables, views, and other database objects have been created successfully.

Use the project documentation and SQL scripts to determine the correct execution order. Do not run scripts blindly against a production database.

### Step 5: Start the Development Server

```bash
npm run dev
```

Open the local URL displayed in your terminal, usually:

```text
http://localhost:5173/
```

Keep the terminal running while using the development server.

## Running the Application

After completing the setup:

1. Start the Vite development server.
2. Open the local URL in a browser.
3. Navigate through the dashboard pages.
4. Check that database-dependent information loads correctly.
5. Verify that the Supabase configuration and required database objects are available if a page reports an error.

The application requires a correctly configured database for database-dependent features to function.

## Security Considerations

- Never commit `.env` files containing actual credentials.
- Do not publish database passwords, service-role keys, access tokens, or other secrets.
- Keep `.env.example` limited to placeholder values.
- Configure Supabase access policies and permissions appropriately.
- Avoid exposing sensitive or identifiable patient information in screenshots, test data, or public documentation.
- Use synthetic or anonymized data for academic demonstrations.
- Review security rules before deploying the application publicly.

## Future Enhancements

Potential future improvements include:

- Role-based access control for hospital staff.
- Enhanced audit logs and operational reports.
- Improved validation and error handling.
- More detailed occupancy visualizations.
- Automated testing and continuous integration.
- Deployment to a public hosting platform.
- Further evaluation and validation of triage and forecasting methods.

These are proposed enhancements and should not be considered completed features unless implemented.

## Team Members

| No. | Team Member | Responsibility |
|---|---|---|
| 1 | [Aadit Pansare] | [Frontend] |
| 2 | [Vaibhavi Jumle] | [database] |
| 3 | [Asma Shaikh] | [Backend] |

## Repository

**Public GitHub Repository:**  
https://github.com/Asma-039/medicommand-ai

This repository contains the project source code, database resources, and documentation for academic review and collaborative development.

---

*Developed as an academic project to demonstrate database management, web application development, hospital resource coordination, and decision-support concepts.*
