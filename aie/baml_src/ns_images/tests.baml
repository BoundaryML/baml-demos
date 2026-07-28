test "image_basic" with MyCustomRetry(3) {
    let img = image.from_file("./test_data/image_one.png", null);
    let goal = "a founder building a programming language";
    let judge = evaluate_image(img, goal);
    log.info(judge.to_string());
    assert.is_true(judge.score > 0.5);
}

testset "disk" with testing.PassRate(0.7) {
    // load all images from the test_data directory
    let images = baml.fs.read_dir("./test_data");
    for (let img in images) {
        test `image: ${img.name}` {
            let img = image.from_file(img.name, null);
            let goal = "a founder building a programming language";
            let judge = evaluate_image(img, goal);
            log.info(judge.to_string());
            assert.is_true(judge.score > 0.5);
        }
    }
}

function MyCustomRetry(max_attempts: int) -> testing.TestRunner {
    if (max_attempts <= 0) {
        baml.sys.panic("testing.Retry requires max_attempts > 0")
    } else {
        null
    }

    return (run_once) -> testing.TestReportThunk {
        () -> testing.TestReport {
            let runs: testing.RunReport[] = [];
            let passed = false;
            let attempts = 0;
            while (attempts < max_attempts && !passed) {
                let report = run_once();
                attempts += 1;
                for (let run in report.runs) {
                    runs.push(run)
                }
                if (report.outcome == "pass") {
                    passed = true
                } else {
                    null
                }
            }
            let outcome: testing.Outcome = if (passed) {
                "pass"
            } else {
                "fail"
            };
            testing.TestReport { outcome: outcome, runs: runs }
        }
    };
}
