import os
from flask import Flask, render_template
from dotenv import load_dotenv

# .env project root par hai (auto-deploy-system/.env)
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '..', '.env'))

from detect_routes import detect_bp
from deploy_routes import deploy_bp

app = Flask(__name__)
app.register_blueprint(detect_bp)
app.register_blueprint(deploy_bp)


@app.route('/')
def home():
    return render_template('dashboard.html')


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
