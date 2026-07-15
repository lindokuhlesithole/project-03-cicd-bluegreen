from flask import Flask, jsonify
import os

app = Flask(__name__)
version = os.environ.get("VERSION", "1.0.0")

@app.route("/")
def index():
    return f"<h1>CI/CD Deployment</h1><p>Version: {version}</p>"

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "version": version})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
