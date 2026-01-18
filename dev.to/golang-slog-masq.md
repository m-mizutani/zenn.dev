---
title: "Redacting Sensitive Data in Go's slog: A Practical Guide with masq"
tags: go,logging,security,slog
published: false
---

Logging is essential for debugging, monitoring, and auditing. But here's the catch—**logs can accidentally expose sensitive data** like passwords, API tokens, or personal information. Once sensitive data lands in your logs, removing it becomes a nightmare, especially when logs are immutable by design for compliance reasons.

In this post, I'll show you how to automatically redact sensitive values from your structured logs using Go's standard `log/slog` package and my open-source library [masq](https://github.com/m-mizutani/masq).

## The Problem: Sensitive Data Leaks in Logs

Consider a typical scenario: you're logging a user struct for debugging purposes.

```go
type User struct {
    ID       string
    Email    string
    APIToken string
}

func main() {
    user := User{
        ID:       "u123",
        Email:    "alice@example.com",
        APIToken: "sk-secret-token-12345",
    }
    slog.Info("user logged in", "user", user)
}
```

Output:

```
level=INFO msg="user logged in" user="{ID:u123 Email:alice@example.com APIToken:sk-secret-token-12345}"
```

Oops. The API token is now in your logs, potentially accessible to anyone with log access, stored for months or years, and nearly impossible to delete.

## slog's Built-in Solution: LogValuer

Go's `slog` package (part of the standard library since Go 1.21) provides `LogValuer` interface for customizing how values appear in logs:

```go
type APIToken string

func (APIToken) LogValue() slog.Value {
    return slog.StringValue("[REDACTED]")
}

func main() {
    token := APIToken("sk-secret-token-12345")
    slog.Info("token received", "token", token)
}
```

Output:

```
level=INFO msg="token received" token=[REDACTED]
```

This works for direct values. However, **LogValuer doesn't work for struct fields**:

```go
type APIToken string

func (APIToken) LogValue() slog.Value {
    return slog.StringValue("[REDACTED]")
}

type Credentials struct {
    UserID string
    Token  APIToken
}

func main() {
    creds := Credentials{
        UserID: "u123",
        Token:  "sk-secret-token-12345",
    }
    slog.Info("credentials", "creds", creds)
}
```

Output (token is exposed!):

```
level=INFO msg=credentials creds="{UserID:u123 Token:sk-secret-token-12345}"
```

When you log a struct, slog uses reflection and bypasses the `LogValue()` method on nested fields. This is a significant limitation for real-world applications.

## Enter masq: Automatic Deep Redaction

I built [masq](https://github.com/m-mizutani/masq) to solve this problem. It hooks into slog's `ReplaceAttr` option and recursively inspects all logged values—including nested structs—to redact sensitive data.

### Basic Usage

```go
package main

import (
    "log/slog"
    "os"

    "github.com/m-mizutani/masq"
)

type EmailAddr string

type User struct {
    ID    string
    Email EmailAddr
}

func main() {
    // Create a logger with masq redaction
    logger := slog.New(
        slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
            ReplaceAttr: masq.New(masq.WithType[EmailAddr]()),
        }),
    )

    user := User{
        ID:    "u123",
        Email: "alice@example.com",
    }

    logger.Info("user registered", "user", user)
}
```

Output:

```json
{
  "time": "2026-01-18T12:00:00.000Z",
  "level": "INFO",
  "msg": "user registered",
  "user": {
    "ID": "u123",
    "Email": "[FILTERED]"
  }
}
```

The email is automatically redacted, even though it's nested inside the struct.

## Redaction Strategies

masq offers multiple ways to identify sensitive data:

### 1. By Custom Type

Define sensitive data as distinct types and redact them:

```go
type Password string
type CreditCard string

masq.New(
    masq.WithType[Password](),
    masq.WithType[CreditCard](),
)
```

### 2. By Struct Tag

Mark sensitive fields with a struct tag:

```go
type User struct {
    ID       string
    Password string `masq:"secret"`
    SSN      string `masq:"secret"`
}

masq.New(masq.WithTag("secret"))
```

### 3. By Field Name

Target specific field names:

```go
masq.New(
    masq.WithFieldName("Password"),
    masq.WithFieldName("APIKey"),
)
```

### 4. By Field Prefix

Redact all fields starting with a prefix:

```go
type Config struct {
    SecretKey      string  // redacted
    SecretToken    string  // redacted
    PublicEndpoint string  // not redacted
}

masq.New(masq.WithFieldPrefix("Secret"))
```

### 5. By Regex Pattern

Match values against patterns (useful for credit cards, phone numbers, etc.):

```go
import "regexp"

// Redact potential credit card numbers (16 digits)
cardPattern := regexp.MustCompile(`\b\d{16}\b`)

masq.New(masq.WithRegex(cardPattern))
```

### 6. By String Content

Redact any value containing a specific string:

```go
masq.New(masq.WithContain("Bearer "))
```

## Combining Multiple Strategies

You can combine multiple redaction rules:

```go
logger := slog.New(
    slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
        ReplaceAttr: masq.New(
            // Redact by type
            masq.WithType[Password](),
            masq.WithType[APIToken](),

            // Redact by struct tag
            masq.WithTag("secret"),

            // Redact fields with "Secret" prefix
            masq.WithFieldPrefix("Secret"),

            // Redact phone numbers
            masq.WithRegex(regexp.MustCompile(`^\+[1-9]\d{10,14}$`)),
        ),
    }),
)
```

## Real-World Example

Here's a complete example showing masq in a typical web application context:

```go
package main

import (
    "log/slog"
    "os"
    "regexp"

    "github.com/m-mizutani/masq"
)

type (
    Password  string
    AuthToken string
)

type LoginRequest struct {
    Username string
    Password Password
}

type UserSession struct {
    UserID      string
    AuthToken   AuthToken
    Email       string `masq:"pii"`
    PhoneNumber string
}

func main() {
    // Configure comprehensive redaction
    logger := slog.New(
        slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
            ReplaceAttr: masq.New(
                masq.WithType[Password](),
                masq.WithType[AuthToken](),
                masq.WithTag("pii"),
                masq.WithRegex(regexp.MustCompile(`^\+[1-9]\d{10,14}$`)), // phone numbers
            ),
        }),
    )
    slog.SetDefault(logger)

    // Simulate login flow
    req := LoginRequest{
        Username: "alice",
        Password: "super-secret-password",
    }
    slog.Info("login attempt", "request", req)

    session := UserSession{
        UserID:      "u123",
        AuthToken:   "tok_abc123xyz",
        Email:       "alice@example.com",
        PhoneNumber: "+14155551234",
    }
    slog.Info("session created", "session", session)
}
```

Output:

```json
{"time":"2026-01-18T12:00:00.000Z","level":"INFO","msg":"login attempt","request":{"Username":"alice","Password":"[FILTERED]"}}
{"time":"2026-01-18T12:00:00.000Z","level":"INFO","msg":"session created","session":{"UserID":"u123","AuthToken":"[FILTERED]","Email":"[FILTERED]","PhoneNumber":"[FILTERED]"}}
```

All sensitive data is automatically redacted while preserving the structure and non-sensitive fields.

## Best Practices

1. **Define custom types for sensitive data**: Instead of using `string` for passwords or tokens, create distinct types like `type Password string`. This makes redaction explicit and catches issues at compile time.

2. **Use struct tags for external data**: When working with third-party structs or database models, use the `masq:"secret"` tag to mark sensitive fields.

3. **Apply regex patterns carefully**: Regex matching runs on every string value, so use specific patterns to avoid performance issues.

4. **Test your redaction**: Write tests that verify sensitive data doesn't appear in log output.

5. **Default to redaction**: When in doubt, redact. It's easier to remove redaction than to clean up leaked data.

## Limitations

- **Private map fields**: masq cannot reliably clone embedded private map types—they become nil. Use struct fields for sensitive data.
- **Performance**: Deep inspection has some overhead. For high-throughput systems, consider sampling or async logging.

## Conclusion

Preventing sensitive data leaks in logs is crucial for security and compliance. While slog's `LogValuer` helps with direct values, masq extends this protection to nested structs and provides flexible redaction strategies.

Give [masq](https://github.com/m-mizutani/masq) a try and let me know what you think!

---

*If you found this helpful, feel free to star the repo on GitHub or share your feedback in the comments below.*
