# Papermark - GCP Cloud Run Deployment Guide

This guide explains how to deploy a private, professional instance of **Papermark** on Google Cloud Platform (GCP).

Unlike the standard setup, this version is designed for **Zero-Local-State**. This means no data is stored on your server or your computer; everything lives securely in professional cloud services, making your installation easy to update and impossible to lose.

---

## 🏗 Architecture Overview
To keep the app fast and secure, we use a "best-in-class" stack:
*   **The Brain (Compute):** Google Cloud Run. It runs the app only when someone visits it, saving you money.
*   **The Memory (Database):** Google Cloud SQL (Postgres). A managed database that handles your user data and document metadata.
*   **The Filing Cabinet (Storage):** Google Cloud Storage. Your PDFs and documents live here, encrypted and safe.
*   **The Vault (Secrets):** GCP Secret Manager. Instead of a local .env file, we store every password and key in a single, encrypted vault in the cloud.
*   **The Postman (Email):** Resend. Handles "Magic Links" so you don't need to manage passwords.
*   **The Traffic Control (Queues):** Upstash QStash & Redis. Manages background tasks and ensures large file uploads don't fail.
*   **The Dashboard (Analytics):** Tinybird. Tracks who viewed your documents and for how long.

---

## 🔍 Why is this different from Vercel? (Specifics)
If you are used to Vercel or local hosting, GCP requires a slightly different mindset:

*   **Statelessness:** You cannot save files "to the folder" in Cloud Run. They will disappear. Everything must go to the Cloud Storage bucket.
*   **The Secret Manager is the "Source of Truth":** We do not use a local .env file for production. When you run our deployment scripts, they pull the latest configuration directly from your GCP Vault.
*   **The Database Tunnel:** Because your database is locked down for security, your computer cannot talk to it directly. Our scripts use a "Proxy" to create a temporary, secure tunnel whenever you need to update the database structure.
*   **S3-Compatible Storage:** While we use Google Cloud Storage, we configure it to "speak" the S3 language so that Papermark’s built-in file handling works perfectly without complex code changes.

---

## Phase 1: External Services Provisioning
Before building in Google Cloud, collect the "keys to the house" from these providers. 

> **Important:** Create a temporary Notepad file to copy and paste these keys as you go. **Never share this file.**

### 1. Resend (Email/Auth)
*   Create a free account at [Resend.com](https://resend.com).
*   Add and verify your domain in the **Domains** section.
*   Generate an API Key with "Full Access."
*   **Save as:** `RESEND_API_KEY`

### 2. Tinybird (Analytics)
*   Create an account at [Tinybird.co](https://tinybird.co).
*   Create a new Workspace.
*   Find your **Admin Token** in the dashboard.
*   Note your **Region** from the URL (e.g., `europe-west2`).
*   **Save as:** `TINYBIRD_TOKEN`

### 3. Upstash (Queues & Rate Limiting)
*   Create an account at [Upstash.com](https://upstash.com).
*   **Redis:** Create a Database. Copy the **REST URL** and **REST Token**.
*   **QStash:** Go to the QStash tab. Copy the **URL**, **Token**, **Current Signing Key**, and **Next Signing Key**.
*   **Save as:** `UPSTASH_REDIS_...` and `QSTASH_...`

### 4. Security Secrets
Open your Terminal and run `openssl rand -base64 32` three separate times.
*   **Save as:**
    1. `NEXTAUTH_SECRET`
    2. `NEXT_PRIVATE_DOCUMENT_PASSWORD_KEY`
    3. `NEXT_PRIVATE_VERIFICATION_SECRET`

---

## Phase 2: GCP Infrastructure Setup

### 1. Cloud SQL (The Database)
*   **Create Instance:** Search for **SQL**, choose **PostgreSQL**.
*   **ID:** `dataroom`.
*   **Password:** Set a strong password for the `postgres` user. **Save for Section 0 & 3.**
*   **Config:** Select **Cloud SQL Enterprise** -> **Sandbox** preset.
*   **Connections:** Select **Public IP**. Leave "Authorized Networks" **blank**.
*   **Security:** Set **SSL Mode** to `Allow only SSL connections`.
*   **Connection Name:** Find this on the Overview page (e.g., `project-id:region:dataroom`). **Save for Section 0 & 3.**

### 2. Cloud Storage (The File Cabinet)
*   **Create Bucket:** Search for **Buckets**.
*   **Name:** Give it a unique, generic name (e.g., `company-document-vault`).
*   **Class:** **Standard**.
*   **Access Control:** **Uniform**.

### 3. Isolated Storage Keys
1.  Search for **Service Accounts**, create one named `papermark-storage-sa`.
2.  In your **Bucket > Permissions**, click **Grant Access**. Add the service account email with the role **Storage Object Admin**.
3.  Go to **Cloud Storage > Settings > Interoperability**. Create a key for the service account.
4.  **Save as:** `NEXT_PRIVATE_UPLOAD_ACCESS_KEY_ID` (starts with `GOOG`) and `NEXT_PRIVATE_UPLOAD_SECRET_ACCESS_KEY`.

### 4. Enable Required APIs
Search for and enable:
*   **Cloud SQL Admin API**
*   **Secret Manager API**
*   **Cloud Run Admin API**

---

## Phase 3: Assembling your Configuration
Assemble these into your `dataroom` secret payload. 

### Section 0: Deployment Variables
*   `GCP_PROJECT`: Your Project ID.
*   `REGION`: Your chosen region (e.g., `europe-west3`).
*   `SERVICE_NAME`: `papermark`.
*   `CLOUD_SQL_INSTANCE`: The connection name from Phase 2.
*   `DB_USER`: `postgres`.
*   `DB_PASS`: Your database password.

### Section 1: Core Application URLs
Use your full subdomain (e.g., `https://documents.yourcompany.com`) for:
*   `NEXT_PUBLIC_APP_URL`
*   `NEXTAUTH_URL`
*   `NEXT_PUBLIC_BASE_URL`
*   `NEXT_PUBLIC_MARKETING_URL`
*   `NEXT_PUBLIC_APP_BASE_HOST`: Just the domain (e.g., `documents.yourcompany.com`).

### Section 2: Security & Encryption
The three random strings from Phase 1.

### Section 3: Database (Socket Format)
`postgresql://[USER]:[PASSWORD]@localhost/papermark?host=/cloudsql/[CONNECTION_NAME]`

### Section 4: Storage (GCS S3 API)
*   `NEXT_PUBLIC_UPLOAD_TRANSPORT`: `s3`
*   `NEXT_PRIVATE_UPLOAD_BUCKET`: Your bucket name.
*   `NEXT_PRIVATE_UPLOAD_DISTRIBUTION_HOST`: `[bucket-name].storage.googleapis.com`
*   `NEXT_PRIVATE_UPLOAD_ENDPOINT`: `https://storage.googleapis.com`
*   `NEXT_PRIVATE_UPLOAD_REGION`: `auto`
*   `NEXT_PRIVATE_UPLOAD_ACCESS_KEY_ID`: Your `GOOG...` key.
*   `NEXT_PRIVATE_UPLOAD_SECRET_ACCESS_KEY`: Your secret key.

### Section 5: Email (Resend)
`RESEND_API_KEY`: From Phase 1.

### Section 6: Analytics (Tinybird)
*   `TINYBIRD_TOKEN`: Admin Token.
*   `NEXT_PUBLIC_TINYBIRD_TRACKER_URL`: (e.g., `https://api.gcp-eu-west2.tinybird.co` for EU).

### Section 7: Queues & Rate Limiting (Upstash)
Copy `QSTASH_URL`, `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`, `UPSTASH_REDIS_REST_LOCKER_URL`, and `UPSTASH_REDIS_REST_LOCKER_TOKEN` from the Upstash consoles.

---

## Phase 4: Storing Secrets & Granting Permissions
1.  **Create Secret:** Search for **Secret Manager**, create a secret named `dataroom`.
2.  **Value:** Paste your entire assembled configuration.
3.  **Grant Access:** In the secret's **Permissions** tab, click **Grant Access**. Add your **Compute Engine default service account** (it looks like `123456789-compute@developer.gserviceaccount.com`) and assign it the **Secret Manager Secret Accessor** role.
4.  **Crucial Build Permissions:** To ensure Google Cloud can actually build and save your application, go to **IAM & Admin > IAM**. Find that exact same Compute Engine default service account, click the pencil icon to edit, and add these two additional roles:
    * **Logs Writer** (Allows you to see the build logs)
    * **Artifact Registry Admin** (Allows GCP to save your compiled Docker container)

---

## Phase 5: The First Launch (Cloud Shell)
1.  **Open Cloud Shell:** Click the `>_` icon in the GCP top bar.
2.  **Activate Node 22:** Google Cloud Shell sometimes defaults to older versions of Node.js. Papermark requires v22. Run this command first to ensure your environment is ready:
    ```bash
    nvm install 22 && nvm use 22
    ```
3.  **Deploy in one step:** Copy and paste this single line into the Cloud Shell and hit Enter. It will download the code, set the permissions, and start the deployment automatically:
    ```bash
    git clone [https://github.com/crypto-neon/papermark.git](https://github.com/crypto-neon/papermark.git) && cd papermark && chmod +x deploy.sh update.sh && ./deploy.sh
    ```
    
---

## Phase 6: Future Updates
When you want to pull the latest code from GitHub and deploy it:

1.  Open **Cloud Shell**.
2.  Navigate to your folder:
    ```bash
    cd papermark
    ```
3.  Run the update script:
    ```bash
    ./update.sh
    ```

---

## Why this is better than "Automatic" updates
*   **Database Safety:** You control when migrations happen via the script.
*   **Zero Local Setup:** No need to install Node, Docker, or Proxy locally.
*   **Visibility:** Instant access to logs in the Cloud Shell if something fails.

---

## Phase 7: Connecting Your Subdomain
Google Cloud Run makes it very easy to attach your custom domain and will automatically generate a free SSL (HTTPS) certificate for you.

1. **Start the Mapping:**
   * Go to **Cloud Run** in the GCP Console.
   * Click on your `papermark` service.
   * Near the top, click the **Integrations** tab, then click **Add Integration**.
   * Select **Custom Domains - Google Cloud Load Balancing** (or if you see a classic **Manage Custom Domains** option at the very top of the Cloud Run page, click that—it's faster).

2. **Configure the Domain:**
   * Select the `papermark` service.
   * If your domain isn't verified in Google yet, it will ask you to verify ownership via Google Webmaster Central (a quick DNS TXT record).
   * Enter your chosen subdomain (e.g., `documents.yourcompany.com`).
   * Click **Submit** or **Continue**.

3. **Update your DNS:**
   * Google will now display a specific **DNS Record** (usually a `CNAME` pointing to `ghs.googlehosted.com`, or an `A` record with an IP address).
   * Open a new tab and go to your domain registrar (e.g., Cloudflare, GoDaddy, Namecheap).
   * Add a new DNS record matching exactly what Google provided.

4. **Wait for the Magic:**
   * It can take anywhere from 15 minutes to an hour for the internet to recognize the new domain and for Google to issue your SSL certificate. 

---

## Phase 8: The First Login
Once your domain is live and showing the secure padlock icon, it is time to access your data room.

1. Go to your new URL (e.g., `https://documents.yourcompany.com`).
2. Click **Sign In**.
3. Enter the exact Admin email address you provided during the Cloud Shell deployment script.
4. Check your email inbox. Resend will have delivered a "Magic Link."
5. Click the link, and you will be logged into your new, completely private instance of Papermark!