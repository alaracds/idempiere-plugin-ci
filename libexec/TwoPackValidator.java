import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Document;
import org.w3c.dom.Element;

public class TwoPackValidator {
	private static final Pattern FILE_NAME = Pattern.compile("2Pack_(\\d+\\.\\d+\\.\\d+)(?:_[^/]+)?\\.zip");

	public static void main(String[] args) {
		if (args.length != 1) {
			fail("Usage: TwoPackValidator BUNDLE_DIR");
		}
		try {
			validate(Path.of(args[0]));
		} catch (Exception exception) {
			fail(exception.getMessage());
		}
	}

	private static void validate(Path bundleDirectory) throws Exception {
		Path metadataDirectory = bundleDirectory.resolve("META-INF");
		List<Pack> packs = new ArrayList<>();
		try (Stream<Path> paths = Files.list(metadataDirectory)) {
			for (Path path : paths.filter(Files::isRegularFile).toList()) {
				String fileName = path.getFileName().toString();
				Matcher matcher = FILE_NAME.matcher(fileName);
				if (matcher.matches()) {
					packs.add(new Pack(path, matcher.group(1)));
				} else if (fileName.startsWith("2Pack_") && fileName.endsWith(".zip")) {
					throw new IllegalArgumentException("Invalid versioned 2Pack filename: " + fileName);
				}
			}
		}
		if (packs.isEmpty()) {
			throw new IllegalArgumentException("No versioned 2Packs found in " + metadataDirectory);
		}
		packs.sort(Comparator.comparing(Pack::version, TwoPackValidator::compareVersions));
		for (int index = 1; index < packs.size(); index++) {
			if (compareVersions(packs.get(index - 1).version(), packs.get(index).version()) >= 0) {
				throw new IllegalArgumentException("2Pack versions are not strictly increasing");
			}
		}
		for (Pack pack : packs) {
			validatePack(pack);
		}
		String buildProperties = Files.readString(bundleDirectory.resolve("build.properties"));
		if (!buildProperties.matches("(?s).*bin\\.includes\\s*=.*META-INF/.*")) {
			throw new IllegalArgumentException("build.properties does not include META-INF/");
		}
		System.out.println("Validated " + packs.size() + " 2Pack files");
	}

	private static void validatePack(Pack pack) throws Exception {
		try (ZipFile zip = new ZipFile(pack.path().toFile())) {
			var entries = zip.entries();
			ZipEntry firstEntry = entries.hasMoreElements() ? entries.nextElement() : null;
			if (firstEntry == null) {
				throw new IllegalArgumentException(pack.name() + " is empty");
			}
			String firstName = firstEntry.getName();
			int separator = firstName.indexOf('/');
			String parentDirectory = separator >= 0 ? firstName.substring(0, separator) : firstName;
			String expectedEntry = parentDirectory + "/dict/PackOut.xml";
			ZipEntry packOut = zip.getEntry(expectedEntry);
			if (packOut == null) {
				throw new IllegalArgumentException(pack.name() + " is missing " + expectedEntry);
			}
			for (ZipEntry entry : zip.stream().toList()) {
				if (!entry.isDirectory()) {
					try (InputStream input = zip.getInputStream(entry)) {
						input.transferTo(java.io.OutputStream.nullOutputStream());
					}
				}
			}
			try (InputStream input = zip.getInputStream(packOut)) {
				validatePackOut(parse(input), pack);
			}
		}
	}

	private static void validatePackOut(Document document, Pack pack) {
		Element root = document.getDocumentElement();
		if (!"idempiere".equals(root.getNodeName())) {
			throw new IllegalArgumentException(pack.name() + " has an unexpected XML root");
		}
		String client = root.getAttribute("Client");
		String clientId = client.split("-", 2)[0];
		try {
			Integer.parseInt(clientId);
		} catch (NumberFormatException exception) {
			throw new IllegalArgumentException(pack.name() + " has an invalid or missing Client attribute");
		}
		if (!root.hasAttribute("Description")) {
			throw new IllegalArgumentException(pack.name() + " is missing the Description attribute");
		}
	}

	private static Document parse(InputStream input) throws Exception {
		DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
		return factory.newDocumentBuilder().parse(input);
	}

	private static int compareVersions(String left, String right) {
		int[] leftParts = Arrays.stream(left.split("\\.")).mapToInt(Integer::parseInt).toArray();
		int[] rightParts = Arrays.stream(right.split("\\.")).mapToInt(Integer::parseInt).toArray();
		for (int index = 0; index < Math.max(leftParts.length, rightParts.length); index++) {
			int comparison = Integer.compare(index < leftParts.length ? leftParts[index] : 0,
					index < rightParts.length ? rightParts[index] : 0);
			if (comparison != 0) return comparison;
		}
		return 0;
	}

	private static void fail(String message) {
		System.err.println(message == null ? "2Pack validation failed" : message);
		System.exit(1);
	}

	private record Pack(Path path, String version) {
		String name() { return path.getFileName().toString(); }
	}
}
