pipeline {

    agent any

    environment {
        IMAGE_NAME        = "angular-app"
        IMAGE_TAG         = "${BUILD_NUMBER}"
        COMPOSE_DIR       = "/workspace"
        UPSTREAM_CONF     = "/workspace/nginx/conf.d/upstream.conf"
        ASSETS_DIR        = "/workspace/assets"
        HC_MAX_RETRIES    = "5"
        HC_RETRY_DELAY    = "10"
        HC_TIMEOUT        = "5"
        BLUE_CONTAINER    = "app-blue"
        GREEN_CONTAINER   = "app-green"
        NGINX_CONTAINER   = "nginx-proxy"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 20, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        stage('Checkout') {
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

        stage('Install Dependencies') {
            steps {
                echo "📦 [INSTALL] Running npm ci..."
                sh 'npm ci --prefer-offline'
            }
        }

        stage('Build Angular') {
            steps {
                echo "🔨 [BUILD] Building Angular production bundle..."
                sh 'npm run build -- --configuration production'
                echo "✅ [BUILD] dist/ generated successfully"
            }
        }

        stage('Build Docker Image') {
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
                echo "✅ [DOCKER] Image built: ${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }

        stage('Detect Active Environment') {
            steps {
                echo "🔍 [DETECT] Reading active environment from upstream.conf..."
                script {
                    def upstreamContent = sh(
                        script: "cat ${UPSTREAM_CONF}",
                        returnStdout: true
                    ).trim()

                    if (upstreamContent.contains("server app-blue:80")) {
                        env.ACTIVE_ENV         = "blue"
                        env.INACTIVE_ENV       = "green"
                        env.ACTIVE_PORT        = "8081"
                        env.INACTIVE_PORT      = "8082"
                        env.ACTIVE_CONTAINER   = "app-blue"
                        env.INACTIVE_CONTAINER = "app-green"
                    } else {
                        env.ACTIVE_ENV         = "green"
                        env.INACTIVE_ENV       = "blue"
                        env.ACTIVE_PORT        = "8082"
                        env.INACTIVE_PORT      = "8081"
                        env.ACTIVE_CONTAINER   = "app-green"
                        env.INACTIVE_CONTAINER = "app-blue"
                    }
                    echo "✅ [DETECT] Active: ${env.ACTIVE_ENV} → Deploying to: ${env.INACTIVE_ENV}"
                }
            }
        }

        stage('Deploy to Inactive Environment') {
            steps {
                echo "🚀 [DEPLOY] Deploying image to ${env.INACTIVE_ENV} container..."
                script {
                    def envTag = env.INACTIVE_ENV == "blue" ? "BLUE_TAG" : "GREEN_TAG"
                    sh """
                        cd ${COMPOSE_DIR}
                        docker stop ${env.INACTIVE_CONTAINER} || true
                        docker rm -f ${env.INACTIVE_CONTAINER} || true
                        ${envTag}=${IMAGE_TAG} docker compose up -d --no-deps ${env.INACTIVE_CONTAINER}
                        docker network connect blue-green-app_bluegreen ${env.INACTIVE_CONTAINER} || true
                        echo "⏳ Waiting 15s for container to initialize..."
                        sleep 15
                    """
                    echo "✅ [DEPLOY] ${env.INACTIVE_ENV} container updated with build #${BUILD_NUMBER}"
                }
            }
        }

        stage('Health Check') {
            steps {
                echo "❤️  [HEALTH CHECK] Validating ${env.INACTIVE_ENV} container..."
                script {
                    def healthUrl = "http://${env.INACTIVE_CONTAINER}/health"
                    def maxRetries = env.HC_MAX_RETRIES.toInteger()
                    def retryDelay = env.HC_RETRY_DELAY.toInteger()
                    def timeout    = env.HC_TIMEOUT.toInteger()
                    def healthy    = false

                    for (int attempt = 1; attempt <= maxRetries; attempt++) {
                        echo "🔁 [HEALTH CHECK] Attempt ${attempt}/${maxRetries} → ${healthUrl}"

                        def result = sh(
                            script: """
                                set +e
                                response=\$(curl --silent --max-time ${timeout} --write-out "HTTPSTATUS:%{http_code}" "${healthUrl}")
                                http_status=\$(echo "\$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
                                body=\$(echo "\$response" | sed 's/HTTPSTATUS:[0-9]*//g')
                                echo "HTTP Status: \$http_status"
                                echo "Body: \$body"
                                if [ "\$http_status" != "200" ]; then
                                    echo "FAIL: HTTP status is \$http_status (expected 200)"
                                    exit 1
                                fi
                                if echo "\$body" | grep -qiE '"OK"|"healthy"|healthy|OK'; then
                                    echo "PASS: Response contains healthy indicator"
                                    exit 0
                                else
                                    echo "FAIL: Body does not contain OK or healthy"
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
                        error("❌ [HEALTH CHECK] FAILED after ${maxRetries} attempts. Triggering rollback.")
                    }

                    env.HEALTH_CHECK_PASSED = "true"
                    echo "✅ [HEALTH CHECK] ${env.INACTIVE_ENV} is healthy and ready for traffic"
                }
            }
        }

        stage('Switch Traffic') {
            steps {
                echo "🔀 [SWITCH] Redirecting traffic from ${env.ACTIVE_ENV} to ${env.INACTIVE_ENV}..."
                script {
                    def newServer = "app-${env.INACTIVE_ENV}"
                    sh """
                        cat > ${UPSTREAM_CONF} << 'UPEOF'
upstream active_app {
    server ${newServer}:80;
    keepalive 16;
}
UPEOF
                        echo "upstream.conf updated to ${newServer}"
                        docker exec ${NGINX_CONTAINER} nginx -t
                        docker exec ${NGINX_CONTAINER} nginx -s reload
                        echo "✅ Nginx reloaded successfully"
                    """
                    echo "✅ [SWITCH] Traffic now flowing to ${env.INACTIVE_ENV}"
                }
            }
        }

        stage('Update env.json') {
            steps {
                echo "📄 [ENV.JSON] Updating Angular dashboard status file..."
                script {
                    def now = sh(
                        script: "date -u '+%Y-%m-%dT%H:%M:%SZ'",
                        returnStdout: true
                    ).trim()

                    def envJson = """{
  "environment": "${env.INACTIVE_ENV}",
  "version": "${IMAGE_TAG}",
  "gitCommit": "${env.GIT_COMMIT_SHORT}",
  "lastDeploy": "${now}",
  "health": "healthy",
  "buildNumber": "${BUILD_NUMBER}",
  "previousEnvironment": "${env.ACTIVE_ENV}"
}"""

                    sh "mkdir -p ${ASSETS_DIR}"
                    writeFile file: "${ASSETS_DIR}/env.json", text: envJson

                    sh """
                        docker cp ${ASSETS_DIR}/env.json ${env.INACTIVE_CONTAINER}:/usr/share/nginx/html/assets/env.json || true
                        docker cp ${ASSETS_DIR}/env.json ${env.ACTIVE_CONTAINER}:/usr/share/nginx/html/assets/env.json || true
                        echo "✅ env.json copiado a ambos contenedores"
                        cat ${ASSETS_DIR}/env.json
                    """

                    echo "✅ [ENV.JSON] Dashboard updated: ${env.INACTIVE_ENV} / build ${BUILD_NUMBER}"
                }
            }
        }

    }

    post {

        failure {
            script {
                echo "🚨 [ROLLBACK] Pipeline failed! Initiating rollback..."
                if (env.INACTIVE_ENV) {
                    sh """
                        docker stop ${env.INACTIVE_CONTAINER} || true
                        docker rm -f ${env.INACTIVE_CONTAINER} || true
                        echo "✅ ${env.INACTIVE_ENV} stopped. ${env.ACTIVE_ENV} continues serving."
                    """
                }
                echo "🔴 [ROLLBACK] Complete."
            }
        }

        success {
            echo "🎉 [DONE] Deployment successful! Active: ${env.INACTIVE_ENV} (build #${BUILD_NUMBER})"
        }

        always {
            sh "docker image prune -f --filter 'until=72h' || true"
        }
    }
}