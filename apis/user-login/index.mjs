import AWS from "aws-sdk";
import mysql from "mysql2/promise";

AWS.config.update({ region: "eu-north-1" });

const ssm = new AWS.SSM();

export const handler = async (event) => {
  let dbConnection;
  try {
    const bodyJson = JSON.parse(event.body);
    const email = bodyJson.email;
    const password = bodyJson.password;

    if (!email || !password) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          status: false,
          message: "Email or Password is missed.!",
        }),
      };
    }

    //TODO: check the email and password
    //TODO: generate the valid JWT token

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: "Successfully generated the token",
        type: "login",
        status: true,
        idToken: "idToken",
        accessToken: "accessToken",
        refreshToken: "refreshToken",
      }),
    };
  } catch (error) {
    console.log(error);
    return {
      statusCode: 500,
      body: "Server error. Please try again later.!",
    };
  } finally {
    console.log("finally");
    if (dbConnection) {
      console.log("Ended DB connection");
      await dbConnection.end();
    }
  }
};

const dataBaseConnection = async () => {
  const dbConfig = {
    host: await getParameterValue(`/lambda-api-${environment}/database/host`),
    user: await getParameterValue(`/lambda-api-${environment}/database/username`),
    password: await getParameterValue(`/lambda-api-${environment}/database/password`),
    database: await getParameterValue(`/lambda-api-${environment}/database/database`),
  };

  const connection = await mysql.createConnection(dbConfig);

  return connection;
};

const getParameterValue = async (parameterName) => {
  console.info('fetching parameter store value: ', parameterName);
  const result = await ssm
  .getParameter({
    Name: parameterName, 
    WithDecryption: true,
  })
  .promise();
  const parameterValue = result.Parameter.Value;
  console.info('fetched parameter store value');

  return parameterValue;
};

