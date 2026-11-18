// TalkMate AI - Unit Tests for Staging Environment Isolation Guard (SEC-E / Issue A & B)
// Proves all negative and positive guarantees for staging isolation.
// Run with: deno test --allow-env supabase/functions/_shared/test_staging_guard_test.ts

import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  canRunStagingTests,
  assertStagingEnvironment,
  getVerifiedStagingEnvironment,
  getVerifiedStagingPostgresEnvironment,
} from "./test_staging_guard.ts";

function withEnv(vars: Record<string, string | undefined>, callback: () => void) {
  const originalEnv: Record<string, string | undefined> = {};
  for (const k of Object.keys(vars)) {
    originalEnv[k] = Deno.env.get(k);
    if (vars[k] === undefined) {
      Deno.env.delete(k);
    } else {
      Deno.env.set(k, vars[k]!);
    }
  }

  // Also clear any generic variables during isolated runs
  const genericVars = [
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_PUBLISHABLE_KEY",
    "SUPABASE_PUBLISHABLE_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_SECRET_KEY",
    "SUPABASE_SECRET_KEYS",
    "PGHOST",
    "PGUSER",
    "PGPASSWORD",
    "PGDATABASE",
    "PGPORT",
  ];
  for (const g of genericVars) {
    if (!(g in vars)) {
      originalEnv[g] = Deno.env.get(g);
      Deno.env.delete(g);
    }
  }

  try {
    callback();
  } finally {
    for (const [k, v] of Object.entries(originalEnv)) {
      if (v === undefined) {
        Deno.env.delete(k);
      } else {
        Deno.env.set(k, v);
      }
    }
  }
}

// ----------------------------------------------------------------------------
// Section 3.A.4 Tests: Supabase Staging Guard Validation
// ----------------------------------------------------------------------------

Deno.test("Staging Guard: Returns null when opt-in is false or unset", () => {
  withEnv({ TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: undefined }, () => {
    assertEquals(getVerifiedStagingEnvironment(), null);
  });

  withEnv({ TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "false" }, () => {
    assertEquals(getVerifiedStagingEnvironment(), null);
  });
});

Deno.test("Staging Guard: Missing project reference throws error", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: undefined,
      TALKMATE_STAGING_SUPABASE_URL: "https://staging-ref.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub_key",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec_key",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "TALKMATE_STAGING_PROJECT_REF is required"
      );
    }
  );
});

Deno.test("Staging Guard: Missing staging URL throws error", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: undefined,
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub_key",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec_key",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "TALKMATE_STAGING_SUPABASE_URL is required"
      );
    }
  );
});

Deno.test("Staging Guard: Missing staging credentials throws error", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://staging-ref.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: undefined,
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec_key",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY is required"
      );
    }
  );

  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://staging-ref.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub_key",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: undefined,
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "TALKMATE_STAGING_SUPABASE_SECRET_KEY is required"
      );
    }
  );
});

Deno.test("Staging Guard: Generic production variables present but staging variables absent throws error", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      SUPABASE_URL: "https://production-project.supabase.co",
      SUPABASE_PUBLISHABLE_KEY: "mock_prod_pub",
      SUPABASE_SECRET_KEY: "mock_prod_sec",
      TALKMATE_STAGING_PROJECT_REF: undefined,
      TALKMATE_STAGING_SUPABASE_URL: undefined,
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "TALKMATE_STAGING_PROJECT_REF is required"
      );
    }
  );
});

Deno.test("Staging Guard: Correct staging hostname succeeds", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging-project",
      TALKMATE_STAGING_SUPABASE_URL: "https://my-staging-project.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_staging_pub_123",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_staging_sec_456",
    },
    () => {
      const env = getVerifiedStagingEnvironment();
      assertEquals(env?.projectRef, "my-staging-project");
      assertEquals(env?.supabaseUrl, "https://my-staging-project.supabase.co");
      assertEquals(env?.publishableKey, "mock_staging_pub_123");
      assertEquals(env?.secretKey, "mock_staging_sec_456");
    }
  );
});

Deno.test("Staging Guard: Hostname containing project ref but not matching exactly is rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "target-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://evil-target-ref.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "Loose substring matching is strictly forbidden"
      );
    }
  );

  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "target-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://target-ref.supabase.co.attacker.com",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "Loose substring matching is strictly forbidden"
      );
    }
  );
});

Deno.test("Staging Guard: Malicious lookalike hostname is rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "testproject",
      TALKMATE_STAGING_SUPABASE_URL: "https://testproject.supabase.co.evil.org",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "Loose substring matching is strictly forbidden"
      );
    }
  );
});

Deno.test("Staging Guard: Insecure HTTP URL is rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "http://staging-ref.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "must use HTTPS protocol"
      );
    }
  );
});

Deno.test("Staging Guard: URL with embedded credentials is rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://user:password@staging-ref.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "must not contain embedded user credentials in URL"
      );
    }
  );
});

Deno.test("Staging Guard: Unexpected port is rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://staging-ref.supabase.co:8080",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "unexpected port '8080'"
      );
    }
  );
});

Deno.test("Staging Guard: Malformed URL is rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "not_a_valid_url",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "not a syntactically valid URL"
      );
    }
  );
});

Deno.test("Staging Guard: Production project reference is strictly rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "icdbbfsjbslzctshxytd",
      TALKMATE_STAGING_SUPABASE_URL: "https://icdbbfsjbslzctshxytd.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "matches production project reference"
      );
    }
  );
});

// ----------------------------------------------------------------------------
// Section 4.B.7 Tests: PostgreSQL Staging Guard Validation
// ----------------------------------------------------------------------------

Deno.test("Staging Postgres Guard: Generic PGHOST/PGPASSWORD cannot activate staging tests", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      PGHOST: "db.my-staging.supabase.co",
      PGPASSWORD: "generic_password",
      PGUSER: "postgres",
      TALKMATE_STAGING_PGHOST: undefined,
    },
    () => {
      assertThrows(
        () => getVerifiedStagingPostgresEnvironment(),
        Error,
        "TALKMATE_STAGING_PGHOST is required"
      );
    }
  );
});

Deno.test("Staging Postgres Guard: Production host is strictly rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_PGHOST: "db.icdbbfsjbslzctshxytd.supabase.co",
      TALKMATE_STAGING_PGUSER: "postgres",
      TALKMATE_STAGING_PGPASSWORD: "secret_pass",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingPostgresEnvironment(),
        Error,
        "matches production project reference"
      );
    }
  );
});

Deno.test("Staging Postgres Guard: Unrecognized database hostname is rejected", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_PGHOST: "arbitrary-attacker-db.example.com",
      TALKMATE_STAGING_PGUSER: "postgres",
      TALKMATE_STAGING_PGPASSWORD: "secret_pass",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingPostgresEnvironment(),
        Error,
        "does not match expected staging host pattern"
      );
    }
  );
});

Deno.test("Staging Postgres Guard: Valid direct staging db host succeeds", () => {
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_PGHOST: "db.my-staging.supabase.co",
      TALKMATE_STAGING_PGUSER: "postgres",
      TALKMATE_STAGING_PGPASSWORD: "staging_db_secret",
      TALKMATE_STAGING_PGPORT: "5432",
      TALKMATE_STAGING_PGDATABASE: "postgres",
    },
    () => {
      const pgEnv = getVerifiedStagingPostgresEnvironment();
      assertEquals(pgEnv?.host, "db.my-staging.supabase.co");
      assertEquals(pgEnv?.port, 5432);
      assertEquals(pgEnv?.user, "postgres");
      assertEquals(pgEnv?.pass, "staging_db_secret");
    }
  );
});

Deno.test("Staging Guard: URL with path segments, queries, or fragments is rejected", () => {
  // Path segment
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://staging-ref.supabase.co/extra/path",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "must not contain path segments"
      );
    }
  );

  // Query parameter
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://staging-ref.supabase.co?token=leak",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "must not contain query parameters"
      );
    }
  );

  // URL fragment
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "staging-ref",
      TALKMATE_STAGING_SUPABASE_URL: "https://staging-ref.supabase.co#fragment",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingEnvironment(),
        Error,
        "must not contain URL fragments"
      );
    }
  );
});

Deno.test("Staging Postgres Guard: Pooler host requires valid project user and allowed port", () => {
  // Valid pooler host and user on transaction port 6543
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_PGHOST: "aws-0-eu-central-1.pooler.supabase.com",
      TALKMATE_STAGING_PGUSER: "postgres.my-staging",
      TALKMATE_STAGING_PGPASSWORD: "secret_pooler_pass",
      TALKMATE_STAGING_PGPORT: "6543",
      TALKMATE_STAGING_PGDATABASE: "postgres",
    },
    () => {
      const pgEnv = getVerifiedStagingPostgresEnvironment();
      assertEquals(pgEnv?.host, "aws-0-eu-central-1.pooler.supabase.com");
      assertEquals(pgEnv?.port, 6543);
      assertEquals(pgEnv?.user, "postgres.my-staging");
    }
  );

  // Pooler host with user not matching project reference is rejected
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_PGHOST: "aws-0-eu-central-1.pooler.supabase.com",
      TALKMATE_STAGING_PGUSER: "postgres.wrong-project-ref",
      TALKMATE_STAGING_PGPASSWORD: "secret_pooler_pass",
      TALKMATE_STAGING_PGPORT: "6543",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingPostgresEnvironment(),
        Error,
        "does not belong to staging project"
      );
    }
  );

  // Pooler host with invalid port (e.g. 8080) is rejected
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_PGHOST: "aws-0-eu-central-1.pooler.supabase.com",
      TALKMATE_STAGING_PGUSER: "postgres.my-staging",
      TALKMATE_STAGING_PGPASSWORD: "secret_pooler_pass",
      TALKMATE_STAGING_PGPORT: "8080",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingPostgresEnvironment(),
        Error,
        "must use port 5432 or 6543"
      );
    }
  );

  // Pooler host with user matching production project ref is rejected
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_PGHOST: "aws-0-eu-central-1.pooler.supabase.com",
      TALKMATE_STAGING_PGUSER: "postgres.icdbbfsjbslzctshxytd",
      TALKMATE_STAGING_PGPASSWORD: "secret_pooler_pass",
      TALKMATE_STAGING_PGPORT: "6543",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingPostgresEnvironment(),
        Error,
        "matches production project reference"
      );
    }
  );

  // Direct db with port other than 5432 is rejected
  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_PGHOST: "db.my-staging.supabase.co",
      TALKMATE_STAGING_PGUSER: "postgres",
      TALKMATE_STAGING_PGPASSWORD: "secret_pass",
      TALKMATE_STAGING_PGPORT: "5433",
    },
    () => {
      assertThrows(
        () => getVerifiedStagingPostgresEnvironment(),
        Error,
        "must use port 5432"
      );
    }
  );
});

Deno.test("Staging Guard: canRunStagingTests and assertStagingEnvironment helpers operate correctly", () => {
  withEnv({ TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: undefined }, () => {
    assertEquals(canRunStagingTests(), false);
    assertThrows(
      () => assertStagingEnvironment("suite-A"),
      Error,
      "without TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS=\"true\""
    );
  });

  withEnv(
    {
      TALKMATE_ALLOW_STAGING_INTEGRATION_TESTS: "true",
      TALKMATE_STAGING_PROJECT_REF: "my-staging",
      TALKMATE_STAGING_SUPABASE_URL: "https://my-staging.supabase.co",
      TALKMATE_STAGING_SUPABASE_PUBLISHABLE_KEY: "mock_pub",
      TALKMATE_STAGING_SUPABASE_SECRET_KEY: "mock_sec",
    },
    () => {
      assertEquals(canRunStagingTests(), true);
      const env = assertStagingEnvironment("suite-B");
      assertEquals(env.projectRef, "my-staging");
      assertEquals(env.supabaseUrl, "https://my-staging.supabase.co");
    }
  );
});
