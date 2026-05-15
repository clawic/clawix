import { execFileSync } from "node:child_process";

const output = execFileSync("git", ["ls-files", "-ci", "--exclude-standard", "-z"], {
  encoding: "utf8",
});

const files = output.split("\0").filter(Boolean);
if (files.length > 0) {
  console.error("tracked ignored files found:");
  for (const file of files) console.error(`- ${file}`);
  console.error("Remove these from Git tracking or narrow the ignore rule.");
  process.exit(1);
}

console.log("tracked ignored check passed");
