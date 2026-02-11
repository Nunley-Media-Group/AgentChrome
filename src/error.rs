use serde::Serialize;

#[repr(u8)]
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
pub enum ExitCode {
    Success = 0,
    GeneralError = 1,
    ConnectionError = 2,
    TargetError = 3,
    TimeoutError = 4,
    ProtocolError = 5,
}

pub struct AppError {
    pub message: String,
    pub code: ExitCode,
}

impl AppError {
    pub fn not_implemented(command: &str) -> Self {
        Self {
            message: format!("{command}: not yet implemented"),
            code: ExitCode::GeneralError,
        }
    }

    pub fn print_json_stderr(&self) {
        let output = ErrorOutput {
            error: &self.message,
            code: self.code as u8,
        };
        let json = serde_json::to_string(&output).expect("failed to serialize error");
        eprintln!("{json}");
    }
}

#[derive(Serialize)]
struct ErrorOutput<'a> {
    error: &'a str,
    code: u8,
}
