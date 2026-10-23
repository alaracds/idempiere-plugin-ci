import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Element;
import org.w3c.dom.Node;

public class PluginXmlValidator {
	public static void main(String[] args) {
		if (args.length != 3) {
			fail("Usage: PluginXmlValidator BUNDLE_DIR TEST_BUNDLE_DIR IDEMPIERE_VERSION");
		}

		try {
			Path bundleDirectory = Path.of(args[0]);
			Path testBundleDirectory = Path.of(args[1]);
			String idempiereVersion = args[2];

			validateBundle(bundleDirectory, idempiereVersion);
			validateBundle(testBundleDirectory, idempiereVersion);
			validateXmlFiles(List.of(bundleDirectory, testBundleDirectory));
		} catch (Exception exception) {
			fail(exception.getMessage());
		}
	}

	private static void validateBundle(Path bundleDirectory, String idempiereVersion) throws Exception {
		if (!Files.isDirectory(bundleDirectory)) {
			throw new IllegalArgumentException("Missing bundle directory: " + bundleDirectory);
		}

		Path pom = bundleDirectory.resolve("pom.xml");
		if (!Files.isRegularFile(pom)) {
			throw new IllegalArgumentException("Missing bundle POM: " + pom);
		}

		Element project = parse(pom);
		Element parent = child(project, "parent");
		String bundleId = bundleDirectory.getFileName().toString();
		if (!"org.idempiere.parent".equals(text(parent, "artifactId"))) {
			throw new IllegalArgumentException(bundleId
					+ " must inherit directly from org.idempiere.parent");
		}

		if (!text(parent, "relativePath").endsWith("org.idempiere.parent/pom.xml")) {
			throw new IllegalArgumentException(bundleId + " has a nonportable iDempiere parent path");
		}

		String artifactId = text(project, "artifactId");
		if (!bundleId.equals(artifactId)) {
			throw new IllegalArgumentException(bundleId + " does not match Maven artifactId " + artifactId);
		}
		if (!"eclipse-plugin".equals(text(project, "packaging"))) {
			throw new IllegalArgumentException(bundleId + " must use eclipse-plugin packaging");
		}

		String revision = text(child(project, "properties"), "revision");
		String expectedRevision = idempiereVersion + "-SNAPSHOT";
		if (!expectedRevision.equals(revision)) {
			throw new IllegalArgumentException(bundleId + " revision " + revision
					+ " does not match " + expectedRevision);
		}
	}

	private static void validateXmlFiles(List<Path> bundleDirectories) throws Exception {
		for (Path bundleDirectory : bundleDirectories) {
			try (Stream<Path> paths = Files.walk(bundleDirectory)) {
				for (Path path : paths.filter(PluginXmlValidator::isPluginXml).toList()) {
					parse(path);
				}
			}
		}
	}

	private static boolean isPluginXml(Path path) {
		if (!Files.isRegularFile(path) || containsSegment(path, "target")) {
			return false;
		}

		String name = path.getFileName().toString();
		return "pom.xml".equals(name)
				|| "plugin.xml".equals(name)
				|| name.endsWith(".xml") && containsSegment(path, "OSGI-INF");
	}

	private static boolean containsSegment(Path path, String segment) {
		for (Path element : path) {
			if (segment.equals(element.toString())) {
				return true;
			}
		}
		return false;
	}

	private static Element parse(Path path) throws Exception {
		DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
		factory.setNamespaceAware(true);
		factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
		factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
		factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
		factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
		factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
		return factory.newDocumentBuilder().parse(path.toFile()).getDocumentElement();
	}

	private static Element child(Element parent, String name) {
		for (Node node = parent.getFirstChild(); node != null; node = node.getNextSibling()) {
			if (node instanceof Element element && name.equals(element.getLocalName())) {
				return element;
			}
		}
		throw new IllegalArgumentException("Missing XML element " + name);
	}

	private static String text(Element parent, String name) {
		return child(parent, name).getTextContent().trim();
	}

	private static void fail(String message) {
		System.err.println(message == null ? "XML validation failed" : message);
		System.exit(1);
	}
}
