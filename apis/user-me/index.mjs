import AWS from "aws-sdk";
import mysql from "mysql2/promise";

AWS.config.update({ region: "eu-north-1" });
const ssm = new AWS.SSM();

const getParameterValue = async (parameterName) => {
  const result = await ssm
    .getParameter({
      Name: parameterName,
      WithDecryption: true,
    })
    .promise();
  const parameterValue = result.Parameter.Value;

  return parameterValue;
};

const environment = await getParameterValue("/lambda-api/environment");

export const handler = async (event) => {
  let dbConnection;
  try {
    const bodyJson = JSON.parse(event.body);
    const email = bodyJson.email;

    if (!email) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          status: false,
          message: "Email is required.!",
        }),
      };
    }

    dbConnection = await dataBaseConnection();

    const user = await getUser(dbConnection, email);
    if (user.length === 0) {
      return {
        statusCode: 203,
        body: JSON.stringify({
          status: false,
          message: "Invalid user.!",
        }),
      };
    }

    return {
      statusCode: 200,
      body: JSON.stringify({
        status: true,
        message: "Success.!",
        user: user
      }),
    };
  } catch (error) {
    console.log(error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        status: false,
        message: "Server error. Please try again later.!",
      }),
    };
  } finally {
    console.log("finally");
    if (dbConnection) {
      console.log("Ended DB connection");
      await dbConnection.end();
    }
  }
};

const getUser = async (dbConnection, email) => {
  console.info("Fetching the user for email :", email);
  const [user] = await dbConnection.execute(
    "SELECT id, name FROM users WHERE email=? AND status=1",
    [email]
  );
  console.info("Fetched the user :", user);
  return user;
};

const dataBaseConnection = async () => {
  const dbConfig = {
    host: await getParameterValue(
      `/lambda-api-${environment}/database/host`
    ),
    user: await getParameterValue(
      `/lambda-api-${environment}/database/username`
    ),
    password: await getParameterValue(
      `/lambda-api-${environment}/database/password`
    ),
    database: await getParameterValue(
      `/lambda-api-${environment}/database/database`
    ),
  };

  const connection = await mysql.createConnection(dbConfig);

  return connection;
};

