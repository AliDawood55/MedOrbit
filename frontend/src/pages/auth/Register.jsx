import {
    useState
} from "react";

import api from "../../api/axios";

import InputField from "../../components/InputField";


function Register() {


    const [form, setForm] = useState({

        email: "",
        password: "",
        role: "patient",
        firstNameAr: "",
        lastNameAr: ""

    });


    const [message, setMessage] = useState("");



    function change(e) {

        setForm({

            ...form,

            [e.target.name]: e.target.value

        });

    }



    async function submit(e) {

        e.preventDefault();


        try {


            await api.post(
                "/auth/register",
                form
            );


            setMessage(
                "Account created"
            );


        }

        catch (err) {

            setMessage(
                err.response?.data?.error?.message
                ||
                "Register failed"
            );


        }

    }



    return (

        <div className="auth">


            <h1>
                Create Account
            </h1>


            <form onSubmit={submit}>


                <InputField
                    name="email"
                    placeholder="Email"
                    value={form.email}
                    onChange={change}
                />


                <InputField
                    type="password"
                    name="password"
                    placeholder="Password"
                    value={form.password}
                    onChange={change}
                />


                <InputField
                    name="firstNameAr"
                    placeholder="First name Arabic"
                    value={form.firstNameAr}
                    onChange={change}
                />


                <InputField
                    name="lastNameAr"
                    placeholder="Last name Arabic"
                    value={form.lastNameAr}
                    onChange={change}
                />



                <select
                    name="role"
                    value={form.role}
                    onChange={change}
                >

                    <option value="patient">
                        Patient
                    </option>


                    <option value="doctor">
                        Doctor
                    </option>


                </select>



                <button>
                    Register
                </button>


                <p>{message}</p>


            </form>


        </div>

    );


}


export default Register;