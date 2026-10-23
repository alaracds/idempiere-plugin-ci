import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.jar.JarFile;
import java.util.jar.Manifest;
import java.util.stream.Stream;

public class BuildArtifactPackager {
	public static void main(String[] args) {
		if (args.length != 10) {
			fail("Usage: BuildArtifactPackager ARTIFACT_DIR OUTPUT_DIR BUNDLE_ID TEST_BUNDLE_ID IDEMPIERE_VERSION BRANCH COMMIT BUILD JAVA MAVEN");
		}
		try {
			packageArtifacts(args);
		} catch (Exception exception) {
			fail(exception.getMessage());
		}
	}

	private static void packageArtifacts(String[] args) throws Exception {
		Path artifactDirectory = Path.of(args[0]);
		Path outputDirectory = Path.of(args[1]);
		String bundleId = args[2];
		String testBundleId = args[3];
		String idempiereVersion = args[4];
		String branch = args[5];
		String commit = args[6];
		String build = args[7];
		String javaVersion = args[8];
		String mavenVersion = args[9];
		String expectedVersion = "0".equals(build) ? idempiereVersion : idempiereVersion + "." + build;
		String shortCommit = commit.substring(0, Math.min(7, commit.length()));

		Path production = findArtifact(artifactDirectory, bundleId, expectedVersion);
		Path tests = findArtifact(artifactDirectory, testBundleId, expectedVersion);
		Files.createDirectories(outputDirectory);
		Path productionOutput = copy(production, outputDirectory,
				bundleId + "-" + idempiereVersion + "-" + shortCommit + "-b" + build + ".jar");
		Path testsOutput = copy(tests, outputDirectory,
				testBundleId + "-" + idempiereVersion + "-" + shortCommit + "-b" + build + ".jar");

		List<String> twoPacks = twoPacks(productionOutput);
		String checksums = sha256(productionOutput) + "  " + productionOutput.getFileName() + "\n"
				+ sha256(testsOutput) + "  " + testsOutput.getFileName() + "\n";
		Files.writeString(outputDirectory.resolve("SHA256SUMS"), checksums, StandardCharsets.UTF_8);
		Files.writeString(outputDirectory.resolve("build-manifest.json"), manifest(bundleId, testBundleId,
				branch, commit, build, javaVersion, mavenVersion, idempiereVersion,
				productionOutput.getFileName().toString(), testsOutput.getFileName().toString(), twoPacks),
				StandardCharsets.UTF_8);
		System.out.println("Packaged immutable artifacts in " + outputDirectory);
	}

	private static Path findArtifact(Path directory, String bundleId, String expectedVersion) throws Exception {
		List<Path> matches = new ArrayList<>();
		try (Stream<Path> paths = Files.walk(directory)) {
			for (Path path : paths.filter(Files::isRegularFile)
					.filter(candidate -> candidate.getFileName().toString().endsWith(".jar")).toList()) {
				try (JarFile jar = new JarFile(path.toFile())) {
					Manifest manifest = jar.getManifest();
					if (manifest != null && bundleId.equals(symbolicName(manifest))
							&& expectedVersion.equals(manifest.getMainAttributes().getValue("Bundle-Version"))) {
						matches.add(path);
					}
				}
			}
		}
		if (matches.size() != 1) {
			throw new IllegalArgumentException("Expected one " + expectedVersion + " artifact for " + bundleId
					+ "; found " + matches.size());
		}
		return matches.get(0);
	}

	private static String symbolicName(Manifest manifest) {
		String value = manifest.getMainAttributes().getValue("Bundle-SymbolicName");
		return value == null ? null : value.split(";", 2)[0].trim();
	}

	private static Path copy(Path source, Path outputDirectory, String name) throws Exception {
		return Files.copy(source, outputDirectory.resolve(name), StandardCopyOption.REPLACE_EXISTING);
	}

	private static List<String> twoPacks(Path artifact) throws Exception {
		try (JarFile jar = new JarFile(artifact.toFile())) {
			return jar.stream().map(entry -> entry.getName())
					.filter(name -> name.startsWith("META-INF/2Pack_") && name.endsWith(".zip"))
					.map(name -> name.substring("META-INF/".length())).sorted().toList();
		}
	}

	private static String sha256(Path path) throws Exception {
		MessageDigest digest = MessageDigest.getInstance("SHA-256");
		try (InputStream input = Files.newInputStream(path)) {
			byte[] buffer = new byte[8192];
			for (int read; (read = input.read(buffer)) != -1;) digest.update(buffer, 0, read);
		}
		return HexFormat.of().formatHex(digest.digest());
	}

	private static String manifest(String bundle, String testBundle, String branch,
			String commit, String build, String javaVersion, String mavenVersion, String idempiereVersion,
			String artifact, String testArtifact, List<String> twoPacks) {
		String packages = twoPacks.stream().map(value -> "\"" + json(value) + "\"")
				.reduce((left, right) -> left + ", " + right).orElse("");
		return "{\n"
				+ "  \"bundle\": \"" + json(bundle) + "\",\n"
				+ "  \"testBundle\": \"" + json(testBundle) + "\",\n"
				+ "  \"branch\": \"" + json(branch) + "\",\n"
				+ "  \"commit\": \"" + json(commit) + "\",\n"
				+ "  \"jenkinsBuild\": \"" + json(build) + "\",\n"
				+ "  \"java\": \"" + json(javaVersion) + "\",\n"
				+ "  \"maven\": \"" + json(mavenVersion) + "\",\n"
				+ "  \"idempiere\": \"" + json(idempiereVersion) + "\",\n"
				+ "  \"artifact\": \"" + json(artifact) + "\",\n"
				+ "  \"testArtifact\": \"" + json(testArtifact) + "\",\n"
				+ "  \"twoPacks\": [" + packages + "]\n"
				+ "}\n";
	}

	private static String json(String value) {
		return value.replace("\\", "\\\\").replace("\"", "\\\"");
	}

	private static void fail(String message) {
		System.err.println(message == null ? "Build artifact packaging failed" : message);
		System.exit(1);
	}
}
