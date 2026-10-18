// Every discovered provider must satisfy its inherited API and property contracts before runtime tests begin.
const { checkProviders } = require("../../support/CheckProviders");
console.log(`Provider contracts passed: ${checkProviders().join(", ")}`);
