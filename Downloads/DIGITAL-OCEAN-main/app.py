from flask import Flask, render_template
import os

app = Flask(__name__, template_folder=".")

@app.route("/")
def home():
    return render_template("index.html")

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
