import getpass
import psycopg2

# Database connection parameters
DB_HOST = "localhost"
DB_NAME = "bank"
DB_USER = "postgres"
DB_PASSWORD = "databasereza1380"

# Connect to the database
conn = psycopg2.connect(host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD)

# Function to execute a database query
def execute_query(query):
    cur = conn.cursor()
    cur.execute(query)
    result = cur.fetchall()
    cur.close()
    return result

# Function to register a new user
def register():
    username = input("Enter username: ")
    password = getpass.getpass("Enter password: ")
    first_name = input("Enter first name: ")
    last_name = input("Enter last name: ")
    national_id = input("Enter national ID: ")
    date_of_birth = input("Enter date of birth (YYYY/MM/DD): ")
    account_type = input("Enter account type (client/employee): ")

    query = f"""
        INSERT INTO account (username, password, first_name, last_name, national_id, date_of_birth, type, interest_rate)
        VALUES ('{username}', '{password}', '{first_name}', '{last_name}', '{national_id}', '{date_of_birth}', '{account_type}', 0)
    """

    execute_query(query)
    print("User registered successfully.")

# Function to handle user login
def login():
    username = input("Enter username: ")
    password = getpass.getpass("Enter password: ")

    query = f"""
        SELECT username
        FROM account
        WHERE username = '{username}' AND password = '{password}'
    """

    result = execute_query(query)
    if result:
        print("Login successful.")
        # Update login_log table with the login time
        query = f"""
            INSERT INTO login_log (username, login_time)
            VALUES ('{username}', current_timestamp)
        """
        execute_query(query)
    else:
        print("Invalid username or password.")

# Function to handle deposit operation
def deposit():
    amount = float(input("Enter the deposit amount: "))

    # Retrieve the username of the last logged-in user
    query = """
        SELECT username
        FROM login_log
        ORDER BY login_time DESC
        LIMIT 1
    """
    result = execute_query(query)
    if result:
        username = result[0][0]

        # Insert deposit transaction into the transactions table
        query = f"""
            INSERT INTO transactions (type, transaction_time, "from", "to", amount)
            VALUES ('deposit', current_timestamp, '{username}', NULL, {amount})
        """
        execute_query(query)
        print("Deposit successful.")
    else:
        print("No user logged in.")

# Function to handle withdraw operation
def withdraw():
    amount = float(input("Enter the withdrawal amount: "))

    # Retrieve the username of the last logged-in user
    query = """
        SELECT username
        FROM login_log
        ORDER BY login_time DESC
        LIMIT 1
    """
    result = execute_query(query)
    if result:
        username = result[0][0]

        # Check if the account has sufficient balance
        query = f"""
            SELECT amount
            FROM latest_balance
            WHERE accountNumber = '{username}'
        """
        balance = execute_query(query)[0][0]
        if balance >= amount:
            # Insert withdraw transaction into the transactions table
            query = f"""
                INSERT INTO transactions (type, transaction_time, "from", "to", amount)
                VALUES ('withdraw', current_timestamp, '{username}', NULL, {amount})
            """
            execute_query(query)
            print("Withdrawal successful.")
        else:
            print("Insufficient balance.")
    else:
        print("No user logged in.")

# Function to handle transfer operation
def transfer():
    amount = float(input("Enter the transfer amount: "))
    destination_account = input("Enter the destination account number: ")

    # Retrieve the username of the last logged-in user
    query = """
        SELECT username
        FROM login_log
        ORDER BY login_time DESC
        LIMIT 1
    """
    result = execute_query(query)
    if result:
        username = result[0][0]

        # Check if the destination account exists
        query = f"""
            SELECT accountNumber
            FROM latest_balance
            WHERE accountNumber = '{destination_account}'
        """
        if execute_query(query):
            # Insert transfer transactions into the transactions table
            query = f"""
                INSERT INTO transactions (type, transaction_time, "from", "to", amount)
                VALUES ('transfer', current_timestamp, '{username}', '{destination_account}', {amount})
            """
            execute_query(query)
            print("Transfer successful.")
        else:
            print("Destination account does not exist.")
    else:
        print("No user logged in.")

# Main loop
while True:
    print("\n==== Banking System ====")
    print("1. Register")
    print("2. Login")
    print("3. Deposit")
    print("4. Withdraw")
    print("5. Transfer")
    print("0. Exit")

    choice = input("Enter your choice: ")

    if choice == "1":
        register()
    elif choice == "2":
        login()
    elif choice == "3":
        deposit()
    elif choice == "4":
        withdraw()
    elif choice == "5":
        transfer()
    elif choice == "0":
        break
    else:
        print("Invalid choice. Please try again.")

# Close the database connection
conn.close()
