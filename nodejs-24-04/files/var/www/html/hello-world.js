const http = require('http');
const hostname = 'localhost';
const port = 3000;

const helpText = `
<!DOCTYPE html>
<html>
<head>
<title>Welcome to Your NodeJS Server</title>
<style>
    body {
        width: 60em;
        margin: 0 auto;
        font-family: Arial, sans-serif;
        background: #c0c0c0;
    }
    div {
      padding: 30px;
      margin: 30px;
      background: #fff;
      border-radius: 5px;
      border: 1px solid #888;
    }
    code {
      font-size: 16px;
      background: #ddd;
    }
</style>
</head>
<body>
  <div>
    <h1>Welcome to Your NodeJS Server!</h1>
    <h2>Things to do with this script</h2>
    <p>This message is coming to you via a simple NodeJS application that's live on your server! This server is all set up with NodeJS and PM2 for process management.</p>
    <p>This app is running at port 3000. If you want to modify this script, you can:</p>
    <ul>
      <li>SSH into your server and modify this script at <code>/var/www/html/hello-world.js</code>, then restart it by calling <code>pm2 restart hello-world</code>.</li>
      <li>Run <code>pm2 list</code> to see code scheduled to start at boot time.</li>
      <li>Run <code>pm2 delete hello-world</code> to stop running this script and <code>pm2 save</code> to stop it from running on server boot.</li>
    </ul>
    <h2>Accessing Your Server</h2>
    <p>You can access your server using the following methods:</p>
    <ul>
      <li><strong>As root:</strong> SSH into your server using the root user. However, to manage PM2 processes, you need to switch to the <code>nodejs</code> user by running <code>sudo su - nodejs</code>.</li>
      <li><strong>Directly as nodejs:</strong> Use the credentials provided in <code>/root/.nodejs_passwords</code> to log in directly as the <code>nodejs</code> user via SSH or SFTP.</li>
    </ul>    
    <h2>Deploy Your Own Code</h2>
    <ul>
      <li>SSH into your server and upload your NodeJS code.</li>
      <li>Install dependencies by running <code>npm install</code> in your project directory.</li>
      <li>Launch your app by calling <code>pm2 start &lt;your-file&gt;</code>.</li>
      <li>Use a reverse proxy like nginx to map your app's port to an HTTP URL.</li>
    </ul>
  </div>
</body>
</html>
`

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html');
  res.end(helpText);
});

server.listen(port, hostname, () => {
  console.log(`Server running at http://${hostname}:${port}/`);
});
