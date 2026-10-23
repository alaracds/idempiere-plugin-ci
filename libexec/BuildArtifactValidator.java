import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.jar.Attributes;
import java.util.jar.JarFile;
import java.util.jar.Manifest;
import java.util.stream.Stream;

public class BuildArtifactValidator {
	public static void main(String[] args) {
		if (args.length != 6) {
			fail("Usage: BuildArtifactValidator ARTIFACT_DIR BUNDLE_DIR BUNDLE_ID TEST_BUNDLE_DIR TEST_BUNDLE_ID EXPECTED_VERSION");
		}
		try {
			Path artifactDirectory = Path.of(args[0]);
			validateArtifact(artifactDirectory, Path.of(args[1]), args[2], args[5], false);
			validateArtifact(artifactDirectory, Path.of(args[3]), args[4], args[5], true);
		} catch (Exception exception) {
			fail(exception.getMessage());
		}
	}

	private static void validateArtifact(Path artifactDirectory, Path sourceDirectory, String bundleId,
			String expectedVersion, boolean fragment) throws Exception {
		List<Path> matches = new ArrayList<>();
		try (Stream<Path> paths = Files.walk(artifactDirectory)) {
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

		Path artifact = matches.get(0);
		try (JarFile jar = new JarFile(artifact.toFile())) {
			Manifest manifest = jar.getManifest();
			Attributes attributes = manifest.getMainAttributes();
			String actualVersion = attributes.getValue("Bundle-Version");
			if (!expectedVersion.equals(actualVersion)) {
				throw new IllegalArgumentException(bundleId + " artifact version " + actualVersion
						+ " does not match " + expectedVersion);
			}
			if (fragment) {
				String host = attributes.getValue("Fragment-Host");
				if (host == null || host.isBlank()) {
					throw new IllegalArgumentException(bundleId + " artifact is missing Fragment-Host");
				}
			}
			verifyPackagedDirectory(jar, sourceDirectory.resolve("OSGI-INF"), "OSGI-INF");
			verifyPackagedDirectory(jar, sourceDirectory.resolve("META-INF"), "META-INF", "2Pack_", ".zip");
		}
		System.out.println("Validated artifact " + artifact);
	}

	private static String symbolicName(Manifest manifest) {
		String value = manifest.getMainAttributes().getValue("Bundle-SymbolicName");
		return value == null ? null : value.split(";", 2)[0].trim();
	}

	private static void verifyPackagedDirectory(JarFile jar, Path sourceDirectory, String jarDirectory)
			throws Exception {
		verifyPackagedDirectory(jar, sourceDirectory, jarDirectory, "", "");
	}

	private static void verifyPackagedDirectory(JarFile jar, Path sourceDirectory, String jarDirectory,
			String prefix, String suffix) throws Exception {
		if (!Files.isDirectory(sourceDirectory)) return;
		try (Stream<Path> paths = Files.list(sourceDirectory)) {
			for (Path path : paths.filter(Files::isRegularFile).toList()) {
				String name = path.getFileName().toString();
				if (name.startsWith(prefix) && name.endsWith(suffix)
						&& jar.getJarEntry(jarDirectory + "/" + name) == null) {
					throw new IllegalArgumentException(jar.getName() + " is missing " + jarDirectory + "/" + name);
				}
			}
		}
	}

	private static void fail(String message) {
		System.err.println(message == null ? "Build artifact validation failed" : message);
		System.exit(1);
	}
}
