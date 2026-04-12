// ═══════════════════════════════════════════════════════════════════════════════
// Jenkinsfile — Blue/Green Deployment Pipeline
//
// Flow:
//   1. Checkout source
//   2. Install npm dependencies
//   3. Build Angular (ng build --configuration production)
//   4. Build Docker image and push to registry
//   5. Detect active environment (blue/green) from upstream.conf
//   6. Deploy new image to the INACTIVE environment
//   7. Health check the new container (5 retries, 10s delay, 5s timeout)
//   8. If healthy → rewrite upstream.conf + nginx reload (zero-downtime switch)
//   9. Update /assets/env.json consumed by Angular dashboard
//  10. On any failure → rollback (stop inactive container, abort pipeline)
// ═══════════════════════════════════════════════════════════════════════════════

pipeline {

    agent any

    // ── Environment variables ────────────────────────────────────────────────
    environment {
        // Docker registry — set to your registry (Docker Hub, ECR, GCR, etc.)
        REGISTRY          = ""
        IMAGE_NAME        = "angular-app"
        IMAGE_TAG         = "${BUILD_NUMBER}"

        // Path on the Jenkins host where docker-compose.yml lives
        COMPOSE_DIR   = "/workspace"

        // Path to nginx upstream config (mounted volume on host)
        UPSTREAM_CONF = "/workspace/nginx/conf.d/upstream.conf"

        // Path to the assets directory shared with containers
        ASSETS_DIR    = "/workspace/assets"

        // Health check settings
        HC_MAX_RETRIES    = "5"
        HC_RETRY_DELAY    = "10"   // seconds between retries
        HC_TIMEOUT        = "5"    // seconds per curl attempt

        // Container names must match docker-compose.yml
        BLUE_CONTAINER    = "app-blue"
        GREEN_CONTAINER   = "app-green"
        NGINX_CONTAINER   = "nginx-proxy"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 20, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()   // prevent two deployments racing
    }

    stages {

        // ────────────────────────────────────────────────────────────────────
        stage('Checkout') {
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "🔵 [CHECKOUT] Cloning repository..."
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    echo "Commit: ${env.GIT_COMMIT_SHORT}"
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        stage('Install Dependencies') {
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "📦 [INSTALL] Running npm ci..."
                sh 'npm ci --prefer-offline'
            }
        }

        // ────────────────────────────────────────────────────────────────────
        stage('Build Angular') {
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "🔨 [BUILD] Building Angular production bundle..."
                sh 'npm run build -- --configuration production'
                echo "✅ [BUILD] dist/ generated successfully"
            }
        }

        // ────────────────────────────────────────────────────────────────────
        stage('Build & Push Docker Image') {
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "🐳 [DOCKER] Building image ${IMAGE_NAME}:${IMAGE_TAG}..."
                sh """
                    docker build \
                        --tag ${IMAGE_NAME}:${IMAGE_TAG} \
                        --tag ${IMAGE_NAME}:latest \
                        --label git-commit=${GIT_COMMIT_SHORT} \
                        --label build-number=${BUILD_NUMBER} \
                        .
                """
                // Uncomment when using a registry:
                // withCredentials([usernamePassword(
                //     credentialsId: 'docker-registry-creds',
                //     usernameVariable: 'DOCKER_USER',
                //     passwordVariable: 'DOCKER_PASS')]) {
                //     sh "echo $DOCKER_PASS | docker login ${REGISTRY} -u $DOCKER_USER --password-stdin"
                //     sh "docker push ${IMAGE_NAME}:${IMAGE_TAG}"
                //     sh "docker push ${IMAGE_NAME}:latest"
                // }
                echo "✅ [DOCKER] Image built: ${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }

        // ────────────────────────────────────────────────────────────────────
        stage('Detect Active Environment') {
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "🔍 [DETECT] Reading active environment from upstream.conf..."
                script {
                    // Read which server line is active in upstream.conf
                    // Line format: "    server app-blue:80;   # ACTIVE_ENV=blue"
                    def upstreamContent = sh(
                        script: "cat ${UPSTREAM_CONF}",
                        returnStdout: true
                    ).trim()

                    if (upstreamContent.contains("server app-blue:80")) {
                        env.ACTIVE_ENV    = "blue"
                        env.INACTIVE_ENV  = "green"
                        env.ACTIVE_PORT   = "8081"
                        env.INACTIVE_PORT = "8082"
                        env.ACTIVE_CONTAINER   = BLUE_CONTAINER
                        env.INACTIVE_CONTAINER = GREEN_CONTAINER
                    } else {
                        env.ACTIVE_ENV    = "green"
                        env.INACTIVE_ENV  = "blue"
                        env.ACTIVE_PORT   = "8082"
                        env.INACTIVE_PORT = "8081"
                        env.ACTIVE_CONTAINER   = GREEN_CONTAINER
                        env.INACTIVE_CONTAINER = BLUE_CONTAINER
                    }

                    echo "✅ [DETECT] Active: ${ACTIVE_ENV} → Deploying to: ${INACTIVE_ENV}"
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        stage('Deploy to Inactive Environment') {
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "🚀 [DEPLOY] Deploying image to ${INACTIVE_ENV} container..."
                script {
                    def envTag = env.INACTIVE_ENV == "blue" ? "BLUE_TAG" : "GREEN_TAG"

                    sh """
                        cd ${COMPOSE_DIR}

                        # Pull latest image if using registry
                        # docker pull ${IMAGE_NAME}:${IMAGE_TAG}

                        # Update the inactive container with the new image
                        ${envTag}=${IMAGE_TAG} docker compose up -d --no-deps --force-recreate ${INACTIVE_CONTAINER}

                        echo "⏳ Waiting 15s for container to initialize..."
                        sleep 15
                    """
                    echo "✅ [DEPLOY] ${INACTIVE_ENV} container updated with build #${BUILD_NUMBER}"
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        stage('Health Check') {
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "❤️  [HEALTH CHECK] Validating ${INACTIVE_ENV} container..."
                script {
                    def healthUrl = "http://localhost:${INACTIVE_PORT}/health"
                    def maxRetries = env.HC_MAX_RETRIES.toInteger()
                    def retryDelay = env.HC_RETRY_DELAY.toInteger()
                    def timeout    = env.HC_TIMEOUT.toInteger()
                    def healthy    = false

                    for (int attempt = 1; attempt <= maxRetries; attempt++) {
                        echo "🔁 [HEALTH CHECK] Attempt ${attempt}/${maxRetries} → ${healthUrl}"

                        def result = sh(
                            script: """
                                set +e
                                response=\$(curl \
                                    --silent \
                                    --max-time ${timeout} \
                                    --write-out "HTTPSTATUS:%{http_code}" \
                                    "${healthUrl}")

                                http_status=\$(echo "\$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
                                body=\$(echo "\$response" | sed 's/HTTPSTATUS:[0-9]*//g')

                                echo "HTTP Status: \$http_status"
                                echo "Body: \$body"

                                # Validate status code = 200
                                if [ "\$http_status" != "200" ]; then
                                    echo "❌ FAIL: HTTP status is \$http_status (expected 200)"
                                    exit 1
                                fi

                                # Validate body contains "OK" or "healthy"
                                if echo "\$body" | grep -qiE '"OK"|"healthy"|healthy|OK'; then
                                    echo "✅ PASS: Response contains healthy indicator"
                                    exit 0
                                else
                                    echo "❌ FAIL: Body does not contain OK or healthy"
                                    exit 1
                                fi
                            """,
                            returnStatus: true
                        )

                        if (result == 0) {
                            healthy = true
                            echo "✅ [HEALTH CHECK] PASSED on attempt ${attempt}"
                            break
                        } else {
                            echo "⚠️  [HEALTH CHECK] Attempt ${attempt} FAILED"
                            if (attempt < maxRetries) {
                                echo "⏳ Waiting ${retryDelay}s before retry..."
                                sleep(retryDelay)
                            }
                        }
                    }

                    if (!healthy) {
                        // Mark for rollback — caught in post{failure} block
                        error("❌ [HEALTH CHECK] FAILED after ${maxRetries} attempts. Triggering rollback.")
                    }

                    env.HEALTH_CHECK_PASSED = "true"
                    echo "✅ [HEALTH CHECK] ${INACTIVE_ENV} is healthy and ready for traffic"
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        stage('Switch Traffic') {
        // ────────────────────────────────────────────────────────────────────
        // Only reached if health check passed
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "🔀 [SWITCH] Redirecting traffic from ${ACTIVE_ENV} → ${INACTIVE_ENV}..."
                script {
                    def newServer = "app-${INACTIVE_ENV}"

                    // Atomically rewrite upstream.conf
                    sh """
                        cat > ${UPSTREAM_CONF} << 'EOF'
# nginx/conf.d/upstream.conf
# ⚠️  MANAGED BY JENKINS — DO NOT EDIT MANUALLY
# Last updated: build #${BUILD_NUMBER}

upstream active_app {
    server ${newServer}:80;   # ACTIVE_ENV=${INACTIVE_ENV}
    keepalive 16;
}
EOF

                        echo "📝 upstream.conf updated → server ${newServer}:80"

                        # Reload nginx config — zero downtime (no restart)
                        docker exec ${NGINX_CONTAINER} nginx -t
                        docker exec ${NGINX_CONTAINER} nginx -s reload

                        echo "✅ Nginx reloaded successfully"
                    """

                    echo "✅ [SWITCH] Traffic now flowing to ${INACTIVE_ENV}"
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        stage('Update env.json') {
        // ────────────────────────────────────────────────────────────────────
            steps {
                echo "📄 [ENV.JSON] Updating Angular dashboard status file..."
                script {
                    def now = sh(
                        script: "date -u '+%Y-%m-%dT%H:%M:%SZ'",
                        returnStdout: true
                    ).trim()

                    def envJson = """{
  "environment": "${INACTIVE_ENV}",
  "version": "${IMAGE_TAG}",
  "gitCommit": "${GIT_COMMIT_SHORT}",
  "lastDeploy": "${now}",
  "health": "healthy",
  "buildNumber": "${BUILD_NUMBER}",
  "previousEnvironment": "${ACTIVE_ENV}"
}"""

                    // Write env.json to shared assets directory
                    // This is mounted as a volume in the active container
                    sh """
                        mkdir -p ${ASSETS_DIR}
                        cat > ${ASSETS_DIR}/env.json << 'ENVEOF'
${envJson}
ENVEOF
                        echo "✅ env.json written:"
                        cat ${ASSETS_DIR}/env.json
                    """

                    echo "✅ [ENV.JSON] Dashboard updated with ${INACTIVE_ENV} / build ${BUILD_NUMBER}"
                }
            }
        }

    } // end stages

    // ── Post-build actions ───────────────────────────────────────────────────
    post {

        failure {
            script {
                echo "🚨 [ROLLBACK] Pipeline failed! Initiating rollback..."

                // Only roll back the inactive container if it was already deployed
                // (avoid trying to roll back before deploy stage)
                if (env.INACTIVE_ENV) {
                    sh """
                        cd ${COMPOSE_DIR}

                        echo "🛑 Stopping ${INACTIVE_CONTAINER}..."
                        docker stop ${INACTIVE_CONTAINER} || true
                        docker rm -f ${INACTIVE_CONTAINER} || true

                        echo "✅ ${INACTIVE_ENV} container stopped. Active environment (${ACTIVE_ENV}) untouched."
                        echo "⚠️  Traffic was NOT switched. ${ACTIVE_ENV} continues serving users."
                    """

                    // Write failure status to env.json for dashboard visibility
                    def now = sh(
                        script: "date -u '+%Y-%m-%dT%H:%M:%SZ'",
                        returnStdout: true
                    ).trim()

                    sh """
                        mkdir -p ${ASSETS_DIR}
                        cat > ${ASSETS_DIR}/env.json << 'ENVEOF'
{
  "environment": "${ACTIVE_ENV}",
  "health": "rollback",
  "lastFailedDeploy": "${now}",
  "failedBuild": "${BUILD_NUMBER}",
  "note": "Deploy to ${INACTIVE_ENV} failed. Traffic remains on ${ACTIVE_ENV}."
}
ENVEOF
                    """
                }

                echo "🔴 [ROLLBACK] Complete. Review logs for failure cause."
            }
        }

        success {
            echo "🎉 [DONE] Deployment successful! Active environment: ${INACTIVE_ENV} (build #${BUILD_NUMBER})"
        }

        always {
            // Clean up old Docker images to save disk space
            sh """
                docker image prune -f --filter "until=72h" || true
            """
        }
    }

}
