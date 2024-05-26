-- Create the account table
CREATE TABLE account (
  username VARCHAR(255) PRIMARY KEY,
  accountNumber BIGINT UNIQUE,
  password VARCHAR(255),
  first_name VARCHAR(255),
  last_name VARCHAR(255),
  national_id CHAR(10),
  date_of_birth DATE,
  type VARCHAR(255),
  interest_rate DECIMAL(5, 2)
);

-- Create the trigger function
CREATE OR REPLACE FUNCTION account_trigger_function() RETURNS TRIGGER AS $$
BEGIN
  -- Your trigger logic goes here
  -- This function will be triggered whenever there is an INSERT, UPDATE, or DELETE operation on the account table

  RETURN NEW; -- Return the new row after the trigger
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
CREATE TRIGGER account_trigger
AFTER INSERT OR UPDATE OR DELETE ON account
FOR EACH ROW
EXECUTE FUNCTION account_trigger_function();

-- Create the login_log table
CREATE TABLE login_log (
  username VARCHAR(255) REFERENCES account(username),
  login_time TIMESTAMP,
  PRIMARY KEY (username, login_time)
);

-- Create the trigger function
CREATE OR REPLACE FUNCTION login_log_trigger_function() RETURNS TRIGGER AS $$
BEGIN
  -- Update the login_time for the user whenever a new login is inserted
  UPDATE login_log
  SET login_time = NEW.login_time
  WHERE username = NEW.username;

  IF NOT FOUND THEN
    -- If no record exists for the user, insert a new login record
    INSERT INTO login_log (username, login_time)
    VALUES (NEW.username, NEW.login_time);
  END IF;

  RETURN NEW; -- Return the new row after the trigger
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
CREATE TRIGGER login_log_trigger
AFTER INSERT ON login_log
FOR EACH ROW
EXECUTE FUNCTION login_log_trigger_function();

-- Create the transactions table
CREATE TABLE transactions (
  transaction_id SERIAL PRIMARY KEY,
  type VARCHAR(255),
  transaction_time TIMESTAMP,
  "from" BIGINT REFERENCES account(accountNumber),
  "to" BIGINT REFERENCES account(accountNumber),
  amount DECIMAL(10, 2)
);

-- Create a trigger function for ensuring balance integrity
CREATE OR REPLACE FUNCTION check_balance_trigger_function() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.type = 'deposit' THEN
    -- Add the deposited amount to the account balance
    UPDATE latest_balances
    SET amount = amount + NEW.amount
    WHERE accountNumber = NEW."to";
  ELSIF NEW.type = 'withdraw' THEN
    -- Subtract the withdrawn amount from the account balance
    UPDATE latest_balances
    SET amount = amount - NEW.amount
    WHERE accountNumber = NEW."from";
  ELSIF NEW.type = 'transfer' THEN
    -- Subtract the transferred amount from the source account
    UPDATE latest_balances
    SET amount = amount - NEW.amount
    WHERE accountNumber = NEW."from";
    
    -- Add the transferred amount to the destination account
    UPDATE latest_balances
    SET amount = amount + NEW.amount
    WHERE accountNumber = NEW."to";
  ELSIF NEW.type = 'interest' THEN
    -- Add the interest amount to the account balance
    UPDATE latest_balances
    SET amount = amount + (NEW.amount * amount)
    WHERE accountNumber = NEW."to";
  END IF;

  RETURN NEW; -- Return the new row after the trigger
END;
$$ LANGUAGE plpgsql;

-- Create the trigger for balance integrity
CREATE TRIGGER check_balance_trigger
AFTER INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION check_balance_trigger_function();

-- Create a trigger function for preventing negative balances
CREATE OR REPLACE FUNCTION prevent_negative_balance_trigger_function() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.type IN ('withdraw', 'transfer') THEN
    -- Check if the account balance will be negative after the transaction
    IF (SELECT amount FROM latest_balances WHERE accountNumber = NEW."from") - NEW.amount < 0 THEN
      RAISE EXCEPTION 'Insufficient funds for the transaction.';
    END IF;
  END IF;

  RETURN NEW; -- Return the new row after the trigger
END;
$$ LANGUAGE plpgsql;

-- Create the trigger for preventing negative balances
CREATE TRIGGER prevent_negative_balance_trigger
BEFORE INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION prevent_negative_balance_trigger_function();

-- Create the account_balance table
CREATE TABLE account_balance (
  accountNumber BIGINT REFERENCES account(accountNumber),
  balance DECIMAL(10, 2),
  PRIMARY KEY (accountNumber)
);

-- Create the snapshot_log table
CREATE TABLE snapshot_log (
  snapshot_id SERIAL PRIMARY KEY,
  snapshot_timestamp TIMESTAMP
);

-- Create the trigger function for inserting new rows in snapshot_log
CREATE OR REPLACE FUNCTION insert_snapshot_log_trigger_function() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO snapshot_log (snapshot_timestamp)
  VALUES (NOW()); -- Inserts the current timestamp for the snapshot
  
  RETURN NEW; -- Return the new row after the trigger
END;
$$ LANGUAGE plpgsql;

-- Create the trigger for inserting new rows in snapshot_log
CREATE TRIGGER insert_snapshot_log_trigger
AFTER INSERT ON account_balance
FOR EACH STATEMENT
EXECUTE FUNCTION insert_snapshot_log_trigger_function();

-- Create the register procedure
CREATE OR REPLACE PROCEDURE register(
  p_username VARCHAR(255),
  p_password VARCHAR(255),
  p_first_name VARCHAR(255),
  p_last_name VARCHAR(255),
  p_national_id CHAR(10),
  p_date_of_birth DATE,
  p_type VARCHAR(255),
  p_interest_rate DECIMAL(5, 2)
)
LANGUAGE plpgsql
AS $$
BEGIN
  -- Check if the user is at least 13 years old
  IF p_date_of_birth > current_date - interval '13 years' THEN
    RAISE EXCEPTION 'Registration not allowed for users under 13 years old.';
  END IF;

  -- Encrypt the password
  -- Replace the encryption logic with the appropriate method you intend to use
  -- Here, we are using a simple MD5 hash as an example
  p_password := md5(p_password);

  -- Insert the user into the account table
  INSERT INTO account (username, accountNumber, password, first_name, last_name, national_id, date_of_birth, type, interest_rate)
  VALUES (p_username, generate_account_number(), p_password, p_first_name, p_last_name, p_national_id, p_date_of_birth, p_type, p_interest_rate);

  -- Insert the initial balance snapshot into the account_balance table
  INSERT INTO account_balance (accountNumber, balance)
  VALUES (currval(pg_get_serial_sequence('account', 'accountNumber')), 0);

  -- Raise notice to indicate successful registration
  RAISE NOTICE 'Registration successful.';
END;
$$;

-- Create the login procedure
CREATE OR REPLACE PROCEDURE login(
  p_username VARCHAR(255),
  p_password VARCHAR(255)
)
LANGUAGE plpgsql
AS $$
BEGIN
  -- Check if the username and password match
  IF EXISTS (
    SELECT 1
    FROM account
    WHERE username = p_username
      AND password = md5(p_password)
  ) THEN
    -- Insert the login time into the login_log table
    INSERT INTO login_log (username, login_time)
    VALUES (p_username, current_timestamp);
  
    -- Raise notice to indicate successful login
    RAISE NOTICE 'Login successful.';
  ELSE
    RAISE EXCEPTION 'Invalid username or password.';
  END IF;
END;
$$;

-- Create the deposit procedure
CREATE OR REPLACE PROCEDURE deposit(
  p_amount DECIMAL(10, 2)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_username VARCHAR(255);
BEGIN
  -- Get the username of the last logged-in user
  SELECT username INTO v_username
  FROM login_log
  ORDER BY login_time DESC
  LIMIT 1;

  -- Check if the user is logged in
  IF v_username IS NULL THEN
    RAISE EXCEPTION 'No user logged in.';
  END IF;

  -- Insert the deposit transaction into the transactions table
  INSERT INTO transactions (type, transaction_time, "from", "to", amount)
  VALUES ('deposit', current_timestamp, NULL, v_username, p_amount);

  -- Raise notice to indicate successful deposit
  RAISE NOTICE 'Deposit successful.';
END;
$$;

-- Create the withdraw procedure
CREATE OR REPLACE PROCEDURE withdraw(
  p_amount DECIMAL(10, 2)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_username VARCHAR(255);
BEGIN
  -- Get the username of the last logged-in user
  SELECT username INTO v_username
  FROM login_log
  ORDER BY login_time DESC
  LIMIT 1;

  -- Check if the user is logged in
  IF v_username IS NULL THEN
    RAISE EXCEPTION 'No user logged in.';
  END IF;

  -- Check if the account has sufficient balance
  IF p_amount > (SELECT balance FROM account_balance WHERE accountNumber = v_username) THEN
    RAISE EXCEPTION 'Insufficient balance for withdrawal.';
  END IF;

  -- Insert the withdrawal transaction into the transactions table
  INSERT INTO transactions (type, transaction_time, "from", "to", amount)
  VALUES ('withdraw', current_timestamp, v_username, NULL, p_amount);

  -- Raise notice to indicate successful withdrawal
  RAISE NOTICE 'Withdrawal successful.';
END;
$$;

-- Create the transfer procedure
CREATE OR REPLACE PROCEDURE transfer(
  p_amount DECIMAL(10, 2),
  p_destination_account VARCHAR(16)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_username VARCHAR(255);
BEGIN
  -- Get the username of the last logged-in user
  SELECT username INTO v_username
  FROM login_log
  ORDER BY login_time DESC
  LIMIT 1;

  -- Check if the user is logged in
  IF v_username IS NULL THEN
    RAISE EXCEPTION 'No user logged in.';
  END IF;

  -- Check if the account has sufficient balance
  IF p_amount > (SELECT balance FROM account_balance WHERE accountNumber = v_username) THEN
    RAISE EXCEPTION 'Insufficient balance for transfer.';
  END IF;

  -- Check if the destination account exists
  IF NOT EXISTS (SELECT 1 FROM account WHERE accountNumber = p_destination_account) THEN
    RAISE EXCEPTION 'Destination account does not exist.';
  END IF;

  -- Insert the transfer transaction into the transactions table
  INSERT INTO transactions (type, transaction_time, "from", "to", amount)
  VALUES ('transfer', current_timestamp, v_username, p_destination_account, p_amount);

  -- Raise notice to indicate successful transfer
  RAISE NOTICE 'Transfer successful.';
END;
$$;

-- Create the interest_payment procedure
CREATE OR REPLACE PROCEDURE interest_payment()
LANGUAGE plpgsql
AS $$
DECLARE
  v_interest_rate DECIMAL(5, 2);
BEGIN
  -- Get the interest rate for client accounts
  SELECT interest_rate INTO v_interest_rate
  FROM account
  WHERE type = 'client';

  -- Insert interest payment transactions into the transactions table
  INSERT INTO transactions (type, transaction_time, "from", "to", amount)
  SELECT 'interest', current_timestamp, accountNumber, accountNumber, (balance * v_interest_rate)
  FROM account_balance;

  -- Raise notice to indicate successful interest payment
  RAISE NOTICE 'Interest payment successful.';
END;
$$;

-- Create the update_balance procedure
CREATE OR REPLACE PROCEDURE update_balance()
LANGUAGE plpgsql
AS $$
BEGIN
  -- Update the latest_balance table based on transaction events
  UPDATE latest_balance AS lb
  SET amount = lb.amount + COALESCE((
    SELECT SUM(amount)
    FROM transactions
    WHERE ("from" = lb.accountNumber OR "to" = lb.accountNumber)
  ), 0);

  -- Insert a new row into the snapshot_log table
  INSERT INTO snapshot_log (snapshot_timestamp)
  VALUES (current_timestamp);

  -- Create a new table named snapshot_id
  EXECUTE format('CREATE TABLE snapshot_%s (LIKE latest_balance INCLUDING ALL)', (SELECT MAX(snapshot_id) FROM snapshot_log));
  EXECUTE format('INSERT INTO snapshot_%s SELECT * FROM latest_balance', (SELECT MAX(snapshot_id) FROM snapshot_log));

  -- Raise notice to indicate successful balance update and snapshot creation
  RAISE NOTICE 'Balance update and snapshot creation successful.';
END;
$$;

-- Create the check_balance procedure
CREATE OR REPLACE PROCEDURE check_balance()
LANGUAGE plpgsql
AS $$
DECLARE
  v_username VARCHAR(255);
  v_balance DECIMAL(10, 2);
BEGIN
  -- Get the username of the last logged-in user
  SELECT username INTO v_username
  FROM login_log
  ORDER BY login_time DESC
  LIMIT 1;

  -- Check if the user is logged in
  IF v_username IS NULL THEN
    RAISE EXCEPTION 'No user logged in.';
  END IF;

  -- Get the balance of the user's account
  SELECT amount INTO v_balance
  FROM latest_balance
  WHERE accountNumber = v_username;

  -- Raise notice to display the account balance
  RAISE NOTICE 'Account Balance: $%.2f', v_balance;
END;
$$;
