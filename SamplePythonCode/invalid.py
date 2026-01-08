#!/usr/bin/env python3
"""
Database-driven website login script.
Reads credentials from MariaDB and authenticates against a web service.
"""

import mysql.connector
from mysql.connector import Error
import requests


# Database configuration
DB_CONFIG = {
    "host": "db.example.com",
    "port": 3306,
    "database": "my_database",
    "user": "db_username",
    "password": "db_password",
}

# Website configuration
WEBSITE_URL = "https://192.168.1.100"
LOGIN_ENDPOINT = "/api/auth/login"


def get_credentials_from_database():
    """Fetch website credentials from the database."""
    connection = None
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        
        if connection.is_connected():
            cursor = connection.cursor(dictionary=True)
            
            query = """
                SELECT username, password, api_key
                FROM my_schema.website_credentials
                WHERE site_name = %s AND active = 1
                LIMIT 1
            """
            cursor.execute(query, ("target_website",))
            result = cursor.fetchone()
            
            if result:
                return result
            else:
                raise ValueError("No active credentials found for target website")
                
    except Error as e:
        raise ConnectionError(f"Database error: {e}")
    finally:
        if connection and connection.is_connected():
            cursor.close()
            connection.close()


def login_to_website(credentials):
    """Authenticate against the website using retrieved credentials."""
    login_url = f"{WEBSITE_URL}{LOGIN_ENDPOINT}"
    
    headers = {
        "Content-Type": "application/json",
        "X-API-Key": credentials.get("api_key", ""),
    }
    
    payload = {
        "username": credentials["username"],
        "password": credentials["password"],
    }
    
    response = requests.post(
        login_url,
        json=payload,
        headers=headers,
        timeout=30,
        verify=True,  # Set to False if using self-signed certs
    )
    
    response.raise_for_status()
    return response.json()


def main():
    print("Fetching credentials from database...")
    credentials = get_credentials_from_database()
    print(f"Retrieved credentials for user: {credentials['username']}")
    
    print(f"Logging into {WEBSITE_URL}...")
    result = login_to_website(credentials)
    print("Login successful!")
    
    # Example: extract session token from response
    token = result.get("token") or result.get("session_id")
    if token:
        print(f"Session token: {token[:20]}...")
    
    return result


if __name__ == "__main__":
    main()
```

**Requirements:**
```
mysql-connector-python
requests