const server = Bun.serve({
  port: 3001,
  fetch(request) {
    return new Response(
      `<!DOCTYPE html>
      <html>
      <head>
        <title>Test App</title>
        <style>
          body {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            font-family: system-ui, -apple-system, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          }
          .emoji {
            font-size: 200px;
            animation: pulse 2s infinite;
          }
          @keyframes pulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.1); }
          }
          .info {
            position: absolute;
            bottom: 20px;
            color: white;
            text-align: center;
          }
        </style>
      </head>
      <body>
        <div class="emoji">🎉</div>
        <div class="info">
          <p>Test App Running on Port 3001</p>
          <p>Deployed at: ${new Date().toISOString()}</p>
        </div>
      </body>
      </html>`,
      {
        headers: {
          "Content-Type": "text/html",
        },
      }
    );
  },
});

console.log(`Test app running at http://localhost:${server.port}`);