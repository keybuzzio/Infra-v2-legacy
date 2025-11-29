from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/health", methods=["GET"])
def health():
    return jsonify(status="ok", service="keybuzz-api"), 200

@app.route("/", methods=["GET"])
def root():
    return "KeyBuzz API placeholder", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

