import AWS from "aws-sdk";
import mysql from "mysql2/promise";

const ssm = new AWS.SSM();

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
const environment = await getParameterValue('/lambda/environment');

export const handler = async (event) => {
  const token = event.headers.token;
  if (!token) {
    return {
      statusCode: 401,
      body: JSON.stringify({ message: "Unauthorized" }),
    };
  }

  let dbConnection;
  let permission = "Deny";
  let accountArn = "";
  try {
    
    accountArn = await getParameterValue(`/lambda-api-${environment}/api-gateway/account-arn`);
    dbConnection = await dataBaseConnection();

    //TODO: you need to develop a correct function to verify the JWT token or your logic as your needs
    const verifyToken = await verifyJwtToken(token);
    if (verifyToken) {
      permission = "Allow";
    }
    console.log('permission', permission);
    
    const authResponse = {
      principalId: "verifyToken.username",
      policyDocument: {
        Version: "2012-10-17",
        Statement: [
          {
            Action: "execute-api:Invoke",
            Resource: [
              `arn:aws:execute-api:eu-north-1:${accountArn}/*/GET/user/me`,
            ],
            Effect: permission,
          }
        ],
      },
      context: {
        client_id: "verifyToken.client_id",
        username: "verifyToken.username",
      },
    };

    return authResponse;
  } catch (error) {
    console.error("Token verification failed:", error);
    const authResponse = {
      principalId: "123456",
      policyDocument: {
        Version: "2012-10-17",
        Statement: [
          {
            Action: "execute-api:Invoke",
            Resource: [
              `arn:aws:execute-api:eu-north-1:${accountArn}/*/GET/user/me`,
            ],
            Effect: permission,
          }
        ],
      },
    };
    return authResponse;
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

const verifyJwtToken = async (token) => {
  return true;
}


